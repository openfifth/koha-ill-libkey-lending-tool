package Koha::Plugin::Com::PTFSEurope::IncDocs;

# Copyright PTFS Europe 2022
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;
use strict;
use warnings;

use base            qw(Koha::Plugins::Base);
use Koha::DateUtils qw( dt_from_string );

use File::Basename qw( dirname );
use CGI;

use JSON qw( encode_json decode_json to_json );
use C4::Installer;

use Koha::Plugin::Com::PTFSEurope::IncDocs::Lib::API;
use Koha::AdditionalFields;
use Koha::ILL::Request::Workflow;
use Koha::Libraries;
use Koha::Patrons;

our $VERSION = "1.0.0";

our $metadata = {
    name            => 'IncDocs',
    author          => 'PTFS-Europe',
    date_authored   => '2024-11-18',
    date_updated    => "2024-11-18",
    minimum_version => '24.05.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     =>
        'This backend provides the ability to create Interlibrary Loan requests using the LibKey Lending Tool API service.'
};

sub ill_backend {
    my ( $class, $args ) = @_;
    return 'IncDocs';
}

sub name {
    return 'IncDocs';
}

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    $self->{config} = decode_json( $self->retrieve_data('incdocs_config') || '{}' );
    return $self;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );
        my $config   = $self->{config};

        $template->param(
            config => $self->{config},
            cwd    => dirname(__FILE__)
        );
        $self->output_html( $template->output() );
    } else {
        my %blacklist = ( 'save' => 1, 'class' => 1, 'method' => 1 );
        my $hashed    = { map { $_ => ( scalar $cgi->param($_) )[0] } $cgi->param };
        my $p         = {};

        foreach my $key ( keys %{$hashed} ) {
            if ( !exists $blacklist{$key} ) {
                $p->{$key} = $hashed->{$key};
            }
        }

        $self->store_data( { incdocs_config => scalar encode_json($p) } );
        print $cgi->redirect(
            -url => '/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::Com::PTFSEurope::IncDocs&method=configure' );
        exit;
    }
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ($self) = @_;

    return 'IncDocs';
}

sub install() {
    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    my $dt = dt_from_string();
    $self->store_data( { last_upgraded => $dt->ymd('-') . ' ' . $dt->hms(':') } );

    return 1;
}

sub uninstall() {
    return 1;
}

=head2 ILL availability methods

=head3 availability_check_info

Utilized if the AutoILLBackend sys pref is enabled

=cut

sub availability_check_info {
    my ( $self, $params ) = @_;

    my $endpoint = '/api/v1/contrib/' . $self->api_namespace . '/ill_backend_availability_incdocs?metadata=';

    return {
        endpoint => $endpoint,
        name     => $metadata->{name},
    };
}

=head2 ILL backend methods

=head3 new_ill_backend

Required method utilized by I<Koha::ILL::Request> load_backend

=cut

sub new_ill_backend {
    my ( $self, $params ) = @_;

    my $api = Koha::Plugin::Com::PTFSEurope::IncDocs::Lib::API->new($VERSION);
    my $log_tt_dir = dirname(__FILE__) . '/' . name() . '/intra-includes/log/';

    $self->{_api}      = $api;
    $self->{templates} = {
        'INCDOCS_MIGRATE_IN' => $log_tt_dir . 'incdocs_migrate_in.tt',
    };
    $self->{_logger} = $params->{logger} if ( $params->{logger} );

    return $self;
}

=head3 create

Handle the "create" flow

=cut

sub create {
    my ( $self, $params ) = @_;

    my $other = $params->{other};
    my $stage = $other->{stage};

    my $response = {
        cwd            => dirname(__FILE__),
        backend        => $self->name,
        method         => "create",
        stage          => $stage,
        branchcode     => $other->{branchcode},
        cardnumber     => $other->{cardnumber},
        status         => "",
        message        => "",
        error          => 0,
        field_map      => $self->fieldmap_sorted,
        field_map_json => to_json( $self->fieldmap() )
    };

    # Check for borrowernumber, but only if we're not receiving an OpenURL
    if ( !$other->{openurl}
        && ( !$other->{borrowernumber} && defined( $other->{cardnumber} ) ) )
    {
        $response->{cardnumber} = $other->{cardnumber};

        # 'cardnumber' here could also be a surname (or in the case of
        # search it will be a borrowernumber).
        my ( $brw_count, $brw ) =
            _validate_borrower( $other->{'cardnumber'}, $stage );

        if ( $brw_count == 0 ) {
            $response->{status} = "invalid_borrower";
            $response->{value}  = $params;
            $response->{stage}  = "init";
            $response->{error}  = 1;
            return $response;
        } elsif ( $brw_count > 1 ) {

            # We must select a specific borrower out of our options.
            $params->{brw}     = $brw;
            $response->{value} = $params;
            $response->{stage} = "borrowers";
            $response->{error} = 0;
            return $response;
        } else {
            $other->{borrowernumber} = $brw->borrowernumber;
        }

        $self->{borrower} = $brw;
    }

    # Initiate process
    if ( !$stage || $stage eq 'init' ) {

        # First thing we want to do, is check if we're receiving
        # an OpenURL and transform it into something we can
        # understand
        if ( $other->{openurl} ) {

            # We only want to transform once
            delete $other->{openurl};
            $params = _openurl_to_incdocs($params);
        }

        # Pass the map of form fields in forms that can be used by TT
        # and JS
        $response->{field_map}      = $self->fieldmap_sorted;
        $response->{field_map_json} = to_json( $self->fieldmap() );

        # We just need to request the snippet that builds the Creation
        # interface.
        $response->{stage} = 'init';
        $response->{value} = $params;
        return $response;
    }

    # Validate form and perform search if valid
    elsif ( $stage eq 'validate' || $stage eq 'form' ) {

        if ( _fail( $other->{'branchcode'} ) ) {

            # Pass the map of form fields in forms that can be used by TT
            # and JS
            $response->{field_map}      = $self->fieldmap_sorted;
            $response->{field_map_json} = to_json( $self->fieldmap() );
            $response->{status}         = "missing_branch";
            $response->{error}          = 1;
            $response->{stage}          = 'init';
            $response->{value}          = $params;
            return $response;
        } elsif ( !Koha::Libraries->find( $other->{'branchcode'} ) ) {

            # Pass the map of form fields in forms that can be used by TT
            # and JS
            $response->{field_map}      = $self->fieldmap_sorted;
            $response->{field_map_json} = to_json( $self->fieldmap() );
            $response->{status}         = "invalid_branch";
            $response->{error}          = 1;
            $response->{stage}          = 'init';
            $response->{value}          = $params;
            return $response;
        } elsif ( !$self->_validate_metadata($other) ) {
            $response->{field_map}      = $self->fieldmap_sorted;
            $response->{field_map_json} = to_json( $self->fieldmap() );
            $response->{status}         = "invalid_metadata";
            $response->{error}          = 1;
            $response->{stage}          = 'init';
            $response->{value}          = $params;
            return $response;
        } else {
            my $result = $self->create_submission($params);
            $response->{stage}  = 'commit';
            $response->{next}   = "illview";
            $response->{params} = $params;
            return $response;
        }
    }
}

=head3 illview

   View and manage an ILL request

=cut

sub illview {
    my ( $self, $params ) = @_;

    return {
        field_map_json => to_json( fieldmap() ),
        method         => "illview"
    };
}

=head3 edititem

Edit an item's metadata

=cut

sub edititem {
    my ( $self, $params ) = @_;

    # Don't allow editing of requested or completed submissions
    return {
        cwd    => dirname(__FILE__),
        method => 'illlist'
    } if ( $params->{request}->status eq 'REQ' || $params->{request}->status eq 'COMP' );

    my $other = $params->{other};
    my $stage = $other->{stage};
    if ( !$stage || $stage eq 'init' ) {
        my $attrs = $params->{request}->illrequestattributes->unblessed;
        foreach my $attr ( @{$attrs} ) {
            $other->{ $attr->{type} } = $attr->{value};
        }
        return {
            cwd            => dirname(__FILE__),
            error          => 0,
            status         => '',
            message        => '',
            method         => 'edititem',
            stage          => 'form',
            value          => $params,
            field_map      => $self->fieldmap_sorted,
            field_map_json => to_json( $self->fieldmap )
        };
    } elsif ( $stage eq 'form' ) {

        # Update submission
        my $submission = $params->{request};
        $submission->updated( DateTime->now );
        $submission->store;

        # We may be receiving a submitted form due to the user having
        # changed request material type, so we just need to go straight
        # back to the form, the type has been changed in the params
        if ( defined $other->{change_type} ) {
            delete $other->{change_type};
            return {
                cwd            => dirname(__FILE__),
                error          => 0,
                status         => '',
                message        => '',
                method         => 'edititem',
                stage          => 'form',
                value          => $params,
                field_map      => $self->fieldmap_sorted,
                field_map_json => to_json( $self->fieldmap )
            };
        }

        # ...Populate Illrequestattributes
        # generate $request_details
        # We do this with a 'dump all and repopulate approach' inside
        # a transaction, easier than catering for create, update & delete
        my $dbh    = C4::Context->dbh;
        my $schema = Koha::Database->new->schema;
        $schema->txn_do(
            sub {
                # Delete all existing attributes for this request
                $dbh->do(
                    q|
                    DELETE FROM illrequestattributes WHERE illrequest_id=?
                |, undef, $submission->id
                );

                # Insert all current attributes for this request
                my $fields = $self->fieldmap;

                # First insert our IncDocs Lending Tool fields
                foreach my $field ( %{$other} ) {
                    my $value = $other->{$field};
                    if ( $other->{$field}
                        && length $other->{$field} > 0 )
                    {
                        my @bind = (
                            $submission->id,
                            column_exists( 'illrequestattributes', 'backend' ) ? "IncDocs" : (),
                            $field, $value, 0
                        );

                        $dbh->do(
                            q|
                            INSERT IGNORE INTO illrequestattributes
                            (illrequest_id,|
                                . ( column_exists( 'illrequestattributes', 'backend' ) ? q|backend,| : q|| ) . q|
                             type, value, readonly) VALUES
                            (?, ?, ?, ?, ?)
                        |, undef, @bind
                        );
                    }
                }

                # Now insert our core equivalents, if an equivalently named Rapid field
                # doesn't already exist
                foreach my $field ( %{$other} ) {
                    my $value = $other->{$field};
                    if (   $other->{$field}
                        && $fields->{$field}->{ill}
                        && length $other->{$field} > 0
                        && !$fields->{ $fields->{$field}->{ill} } )
                    {
                        my @bind = (
                            $submission->id,
                            column_exists( 'illrequestattributes', 'backend' ) ? "IncDocs" : (),
                            $field, $value, 0
                        );

                        $dbh->do(
                            q|
                            INSERT IGNORE INTO illrequestattributes
                            (illrequest_id,|
                                . ( column_exists( 'illrequestattributes', 'backend' ) ? q|backend,| : q|| ) . q|
                             type, value, readonly) VALUES
                            (?, ?, ?, ?, ?)
                        |, undef, @bind
                        );
                    }
                }
            }
        );

        # Create response
        return {
            cwd            => dirname(__FILE__),
            error          => 0,
            status         => '',
            message        => '',
            method         => 'create',
            stage          => 'commit',
            next           => 'illview',
            value          => $params,
            field_map      => $self->fieldmap_sorted,
            field_map_json => to_json( $self->fieldmap )
        };
    }
}

=head3 do_join

If a field should be joined with another field for storage as a core
value or display, then do it

=cut

sub do_join {
    my ( $self, $field, $metadata ) = @_;
    my $fields = $self->fieldmap;
    my $value  = $metadata->{$field};
    my $join   = $fields->{$field}->{join};
    if ( $join && $metadata->{$join} && $value ) {
        my @to_join = ( $value, $metadata->{$join} );
        $value = join " ", @to_join;
    }
    return $value;
}

=head3 mark_completed

Mark a request as completed (status = COMP).

=cut

sub mark_completed {
    my ($self) = @_;
    $self->status('COMP')->store;
    $self->completed( dt_from_string() )->store;
    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'mark_completed',
        stage   => 'commit',
        next    => 'illview',
    };
}

=head3 migrate

Migrate a request into or out of this backend

=cut

sub migrate {
    my ( $self, $params ) = @_;
    my $other = $params->{other};

    my $stage = $other->{stage};
    my $step  = $other->{step};

    my $fields = $self->fieldmap;

    my $request = Koha::ILL::Requests->find( $other->{illrequest_id} );

    # Record where we're migrating from, so we can log that
    my $migrating_from = $request->backend;

    if ( $request->status eq 'REQ' ) {

        # The orderid is no longer applicable
        $request->orderid(undef);
    }
    $request->status('MIG');
    $request->backend( $self->name );
    $request->updated( DateTime->now );
    $request->store;

    # Translate the core metadata into our schema
    my $all_attrs = $request->illrequestattributes->unblessed;

    # For each attribute, if the property name is a core one we change it to the IncDocs Lending Tool
    # equivalent, otherwise we can skip it as it already exists in the attributes list
    foreach my $attr ( @{$all_attrs} ) {
        my $incdocs_field_name = $self->find_incdocs_property( $attr->{type} );

        # If we've found a IncDocs Lending Tool field name and an attribute doesn't already exist
        # with this name, create a new one
        if ( $incdocs_field_name && !$self->find_illrequestattribute( $all_attrs, $incdocs_field_name ) ) {
            Koha::ILL::Request::Attribute->new(
                {
                    illrequest_id => $request->illrequest_id,

                    # Check required for compatibility with installations before bug 33970
                    column_exists( 'illrequestattributes', 'backend' ) ? ( backend => "IncDocs" ) : (),
                    type  => $incdocs_field_name,
                    value => $attr->{value},
                }
            )->store;
        }
    }

    # Log that the migration took place
    if ( $self->_logger ) {
        my $payload = {
            modulename   => 'ILL',
            actionname   => 'INCDOCS_MIGRATE_IN',
            objectnumber => $request->id,
            infos        => to_json(
                {
                    log_origin    => $self->name,
                    migrated_from => $migrating_from,
                    migrated_to   => $self->name
                }
            )
        };
        $self->_logger->log_something($payload);
    }

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'migrate',
        stage   => 'commit',
        next    => 'illview',
        value   => $params,
    };

}

=head3 _validate_metadata

Ensure the metadata we've got conforms to the order
API specification

=cut

sub _validate_metadata {
    my ( $self, $metadata ) = @_;
    return 1;
}

=head3 create_submission

Create a local submission, for later IncDocs Lending Tool request creation

=cut

sub create_submission {
    my ( $self, $params ) = @_;

    my $unauthenticated_request =
        C4::Context->preference("ILLOpacUnauthenticatedRequest") && !$params->{other}->{borrowernumber};

    my $patron = Koha::Patrons->find( $params->{other}->{borrowernumber} );

    my $request = $params->{request};
    $request->borrowernumber( $patron ? $patron->borrowernumber : undef );
    $request->branchcode( $params->{other}->{branchcode} );
    $request->status( $unauthenticated_request ? 'UNAUTH' : 'NEW' );
    $request->batch_id(
        $params->{other}->{ill_batch_id} ? $params->{other}->{ill_batch_id} : $params->{other}->{batch_id} );
    $request->backend( $self->name );
    $request->placed( DateTime->now );
    $request->updated( DateTime->now );

    $request->store;

    $params->{other}->{type} = 'article';

    # Store the request attributes
    $self->create_illrequestattributes( $request, $params->{other} );

    # Now store the core equivalents
    $self->create_illrequestattributes( $request, $params->{other}, 1 );

    if ($unauthenticated_request) {
        my $unauthenticated_notes_text =
              "Unauthenticated request.\nFirst name: $params->{other}->{'unauthenticated_first_name'}"
            . ".\nLast name: $params->{other}->{'unauthenticated_last_name'}."
            . "\nEmail: $params->{other}->{'unauthenticated_email'}.";
        $request->append_to_note($unauthenticated_notes_text);
        $request->notesopac($unauthenticated_notes_text)->store;
    }

    return $request;
}

=head3

Store metadata for a given request for our IncDocs Lending Tool fields

=cut

sub create_illrequestattributes {
    my ( $self, $request, $metadata, $core ) = @_;

    # Get the canonical list of metadata fields
    my $fields = $self->fieldmap;

    # Get any existing illrequestattributes for this request,
    # so we can avoid trying to create duplicates
    my $existing_attrs = $request->illrequestattributes->unblessed;
    my $existing_hash  = {};
    foreach my $a ( @{$existing_attrs} ) {
        $existing_hash->{ lc $a->{type} } = $a->{value};
    }

    # Iterate our list of fields
    foreach my $field ( keys %{$fields} ) {
        if (
            # If we're working with core metadata, check if this field
            # has a core equivalent
            ( ( $core && $fields->{$field}->{ill} ) || !$core )
            && $metadata->{$field}
            && length $metadata->{$field} > 0
            )
        {
            my $att_type  = $core ? $fields->{$field}->{ill} : $field;
            my $att_value = $metadata->{$field};

            # If core, we might need to join
            if ($core) {
                $att_value = $self->do_join( $field, $metadata );
            }

            # If it doesn't already exist for this request
            if ( !exists $existing_hash->{ lc $att_type } ) {
                my $data = {
                    illrequest_id => $request->illrequest_id,

                    # Check required for compatibility with installations before bug 33970
                    column_exists( 'illrequestattributes', 'backend' ) ? ( backend => "IncDocs" ) : (),
                    type     => $att_type,
                    value    => $att_value,
                    readonly => 0
                };
                Koha::ILL::Request::Attribute->new($data)->store;
            }
        }
    }
}

=head3 prep_submission_metadata

Given a submission's metadata, probably from a form,
but maybe as an ILL::Request::Attributes object,
and a partly constructed hashref, add any metadata that
is appropriate for this material type

=cut

sub prep_submission_metadata {
    my ( $self, $metadata, $return ) = @_;

    $return = $return //= {};

    my $metadata_hashref = {};

    if ( ref $metadata eq "Koha::ILL::Request::Attributes" ) {
        while ( my $attr = $metadata->next ) {
            $metadata_hashref->{ $attr->type } = $attr->value;
        }
    } else {
        $metadata_hashref = $metadata;
    }

    # Get our canonical field list
    my $fields = $self->fieldmap;

    # Iterate our list of fields
    foreach my $field ( keys %{$fields} ) {
        if ( $metadata_hashref->{$field}
            && length $metadata_hashref->{$field} > 0 )
        {
            $metadata_hashref->{$field} =~ s/  / /g;
            if ( $fields->{$field}->{api_max_length} ) {
                $return->{$field} = substr( $metadata_hashref->{$field}, 0, $fields->{$field}->{api_max_length} );
            } else {
                $return->{$field} = $metadata_hashref->{$field};
            }
        }
    }

    return $return;
}

=head3 submit_and_request

Creates a local submission, then uses the returned ID to create
a IncDocs Lending Tool request

=cut

sub submit_and_request {
    my ( $self, $params ) = @_;

    # First we create a submission
    my $submission = $self->create_submission($params);

    # Now use the submission to try and create a request with IncDocs Lending Tool
    return $self->create_request($submission);
}

=head3 create_request

Take a previously created submission and send it to IncDocs Lending Tool
in order to create a request

=cut

sub create_request {
    my ( $self, $submission ) = @_;

    my $metadata = {};
    my $request  = $submission->{request};

    my $incdocs     = Koha::Plugin::Com::PTFSEurope::IncDocs->new;
    my $incdocs_api = $incdocs->new_ill_backend( { logger => Koha::ILL::Request::Logger->new } )->{_api};
    my $config      = eval { decode_json( $incdocs->retrieve_data("incdocs_config") // {} ) };

    my $additional_field =
        Koha::AdditionalFields->search( { name => $config->{library_libraryidfield}, tablename => 'branches' } )->next;
    my $library    = Koha::Libraries->find( $request->branchcode );
    my $incdocs_id = $library->additional_field_values->search(
        { 'record_id' => $library->id, 'field_id' => $additional_field->id } )->next;

    my $requesterLibraryId = $incdocs_id->value;

    # # Make the request with IncDocs Lending Tool via the koha-plugin-IncDocs API
    my $result = $incdocs_api->Create_Fulfillment_Request(
        {
            articleId          => $submission->{other}->{articleId},
            lenderLibraryId    => $submission->{other}->{lenderLibraryId},
            requesterLibraryId => $requesterLibraryId
        }
    );

    if ( $result->{error} ) {
        $request->append_to_note( $result->{error} );
        $request->status('ERROR')->store;
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'confirm',
            stage   => 'commit',
            next    => 'illview',
            value   => {}
        };
    }

    $result->{incdocs_type} = delete $result->{type};
    $result->{type}         = 'article';
    $result->{incdocs_id}   = delete $result->{id};

    $request->orderid( $result->{incdocs_id} );
    $request->status('REQ');
    $request->store;

    $self->create_illrequestattributes( $request, $result );

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'confirm',
        stage   => 'commit',
        next    => 'illview',
        value   => {}
    };
}

=head3 confirm

A wrapper around create_request allowing us to
provide the "confirm" method required by
the status graph

=cut

sub confirm {
    my ( $self, $params ) = @_;

    my $stage = $params->{other}->{stage};
    if ( !$stage || 'availability' eq $stage ) {
        return $self->availability($params);
    } elsif ( 'commit' eq $stage ) {
        return $self->create_request($params);
    }

    my $return = $self->create_request( $params->{request} );

    my $return_value = {
        cwd     => dirname(__FILE__),
        error   => 0,
        status  => "",
        message => "",
        method  => "create",
        stage   => "commit",
        next    => "illview",
        value   => {},
        %{$return}
    };

    return $return_value;
}

=head3 log_request_outcome

Log the outcome of a request to the IncDocs Lending Tool API

=cut

sub log_request_outcome {
    my ( $self, $params ) = @_;

    if ( $self->{_logger} ) {

        # TODO: This is a transitionary measure, we have removed set_data
        # in Bug 20750, so calls to it won't work. But since 20750 is
        # only in 19.05+, they only won't work in earlier
        # versions. So we're temporarily going to allow for both cases
        my $payload = {
            modulename   => 'ILL',
            actionname   => $params->{outcome},
            objectnumber => $params->{request}->id,
            infos        => to_json(
                {
                    log_origin => $self->name,
                    response   => $params->{message}
                }
            )
        };
        if ( $self->{_logger}->can('set_data') ) {
            $self->{_logger}->set_data($payload);
        } else {
            $self->{_logger}->log_something($payload);
        }
    }
}

=head3 get_log_template_path

    my $path = $BLDSS->get_log_template_path($action);

Given an action, return the path to the template for displaying
that action log

=cut

sub get_log_template_path {
    my ( $self, $action ) = @_;
    return $self->{templates}->{$action};
}

=head3 backend_metadata

Return a hashref containing canonical values from the key/value
illrequestattributes store

=cut

sub backend_metadata {
    my ( $self, $request ) = @_;

    my $attrs  = $request->illrequestattributes;
    my $fields = $self->fieldmap;

    my $metadata               = {};
    my $metadata_keyed_on_prop = {};

    while ( my $attr = $attrs->next ) {
        if ( $fields->{ $attr->type } ) {
            my $label = $fields->{ $attr->type }->{label};
            $metadata->{$label} = $attr->value;
            $metadata_keyed_on_prop->{ $attr->type } = $attr->value;
        }
    }

    my $rd_title_key = 'Journal title';
    $metadata->{Title} = $metadata->{$rd_title_key} if $metadata->{$rd_title_key};

    return $metadata;
}

=head3 capabilities

    $capability = $backend->capabilities($name);

Return the sub implementing a capability selected by NAME, or 0 if that
capability is not implemented.

=cut

sub capabilities {
    my ( $self, $name ) = @_;
    my $capabilities = {

        # View and manage a request
        illview => sub { illview(@_); },

        # Migrate
        migrate => sub { $self->migrate(@_); },

        # Return whether we can create the request
        # i.e. the create form has been submitted
        can_create_request => sub { _can_create_request(@_) },

        # This is required for compatibility
        # with Koha versions prior to bug 33716
        should_display_availability => sub { _can_create_request(@_) },

        provides_backend_availability_check => sub { return 1; },

        provides_batch_requests => sub { return 1; },

        # We can create ILL requests with data passed from the API
        create_api => sub { $self->create_api(@_) },

        opac_unauthenticated_ill_requests => sub { return 1; }
    };

    return $capabilities->{$name};
}

=head3 _can_create_request

Given the parameters we've been passed, should we create the request

=cut

sub _can_create_request {
    my ($params) = @_;
    return ( defined $params->{'stage'} ) ? 1 : 0;
}

=head3 status_graph


=cut

sub status_graph {
    return {
        EDITITEM => {
            prev_actions   => ['NEW'],
            id             => 'EDITITEM',
            name           => 'Edited item metadata',
            ui_method_name => 'Edit item metadata',
            method         => 'edititem',
            next_actions   => [],
            ui_method_icon => 'fa-edit',
        },
        ERROR => {
            prev_actions   => [],
            id             => 'ERROR',
            name           => 'Request error',
            ui_method_name => 0,
            method         => 0,
            next_actions   => [ 'COMP', 'EDITITEM', 'MIG', 'KILL' ],
            ui_method_icon => 0,
        },
        COMP => {
            prev_actions   => ['ERROR'],
            id             => 'COMP',
            name           => 'Order Complete',
            ui_method_name => 'Mark completed',
            method         => 'mark_completed',
            next_actions   => [],
            ui_method_icon => 'fa-check',
        },

        # Override REQ so we can rename the button
        # Talk about a sledgehammer to crack a nut
        REQ => {
            prev_actions   => [ 'NEW', 'REQREV', 'QUEUED', 'CANCREQ' ],
            id             => 'REQ',
            name           => 'Requested',
            ui_method_name => 'Request from IncDocs',
            method         => 'confirm',
            next_actions   => [ 'REQREV', 'COMP', 'CHK' ],
            ui_method_icon => 'fa-check',
        },
        MIG => {
            prev_actions   => [ 'NEW', 'REQ', 'GENREQ', 'REQREV', 'QUEUED' ],
            id             => 'MIG',
            name           => 'Switched provider',
            ui_method_name => 'Switch provider',
            method         => 'migrate',
            next_actions   => [ 'REQ', 'GENREQ', 'KILL', 'MIG' ],
            ui_method_icon => 'fa-search',
        },
    };
}

=head3 _fail

=cut

sub _fail {
    my @values = @_;
    foreach my $val (@values) {
        return 1 if ( !$val or $val eq '' );
    }
    return 0;
}

=head3 find_illrequestattribute

=cut

sub find_illrequestattribute {
    my ( $self, $attributes, $prop ) = @_;
    foreach my $attr ( @{$attributes} ) {
        if ( $attr->{type} eq $prop ) {
            return 1;
        }
    }
}

=head3 find_incdocs_property

Given a core property name, find the equivalent IncDocs Lending Tool
name. Or undef if there is not one

=cut

sub find_incdocs_property {
    my ( $self, $core ) = @_;
    my $fields = $self->fieldmap;
    foreach my $field ( keys %{$fields} ) {
        if ( $fields->{$field}->{ill} && $fields->{$field}->{ill} eq $core ) {
            return $field;
        }
    }
}

=head3 _openurl_to_incdocs

Take a hashref of OpenURL parameters and return
those same parameters but transformed to the IncDocs
schema

=cut

sub _openurl_to_incdocs {
    my ($params) = @_;

    my $transform_metadata = {
        atitle  => 'atitle',
        aufirst => 'aufirst',
        aulast  => 'aulast',
        date    => 'date',
        issue   => 'issue',
        volume  => 'volume',
        isbn    => 'isbn',
        issn    => 'issn',
        eissn   => 'eissn',
        doi     => 'doi',
        pmid    => 'pubmedid',
        title   => 'title',
        pages   => 'pages'
    };

    my $return = {};

    # First make sure our keys are correct
    foreach my $meta_key ( keys %{ $params->{other} } ) {

        # If we are transforming this property...
        if ( exists $transform_metadata->{$meta_key} ) {

            # ...do it if we have valid mapping
            if ( length $transform_metadata->{$meta_key} > 0 ) {
                $return->{ $transform_metadata->{$meta_key} } = $params->{other}->{$meta_key};
            }
        } else {

            # Otherwise, pass it through untransformed
            $return->{$meta_key} = $params->{other}->{$meta_key};
        }
    }
    $params->{other} = $return;
    return $params;
}

=head3 create_api

Create a local submission from data supplied via an
API call

=cut

sub create_api {
    my ( $self, $body, $request ) = @_;

    # We are receiving metadata in core schema, we need to
    # translate to IncDocs Lending Tool schema before we can proceed
    # We merge the supplied core metadata with the IncDocs Lending Tool
    # equivalents
    foreach my $attr ( @{ $body->{extended_attributes} } ) {
        my $prop         = $attr->{type};
        my $incdocs_prop = find_core_to_incdocs($prop);
        if ($incdocs_prop) {
            my @value = map { $_->{type} eq $incdocs_prop ? $_->{value} : () } @{ $body->{extended_attributes} };
            $body->{$incdocs_prop} = $value[0];
        }
    }

    # Create a submission from our metadata
    # Mung things into the form create_submission expects
    delete $body->{extended_attributes};

    my $submission = $self->create_submission(
        {
            request => $request,
            other   => $body
        }
    );

    return $submission;
}

=head3 find_core_to_incdocs

Given a core metadata property, find the element
in fieldmap that has that as the "ill" property

=cut

sub find_core_to_incdocs {
    my ($prop) = @_;

    my $fieldmap = fieldmap();

    foreach my $field ( keys %{$fieldmap} ) {
        if ( $fieldmap->{$field}->{ill} && $fieldmap->{$field}->{ill} eq $prop ) {
            return $prop;
        }
    }
}

=head3 fieldmap_sorted

Return the fieldmap sorted by "order"
Note: The key of the field is added as a "key"
property of the returned hash

=cut

sub fieldmap_sorted {
    my ($self) = @_;

    my $fields = $self->fieldmap;

    my @out = ();

    foreach my $key ( sort { $fields->{$a}->{position} <=> $fields->{$b}->{position} } keys %{$fields} ) {
        my $el = $fields->{$key};
        $el->{key} = $key;
        push @out, $el;
    }

    return \@out;
}

=head3 fieldmap

All fields expected by the API

Key = API metadata element name
  hide = Make the field hidden in the form
  no_submit = Do not pass to IncDocs Lending Tool API
  api_max_length = Max length of field enforced by the IncDocs Lending Tool API
  exclude = Do not include on the entry form
  type = Does an element contain a string value or an array of string values?
  label = Display label
  ill   = The core ILL equivalent field
  help = Display help text

=cut

sub fieldmap {
    return {
        title => {
            exclude        => 1,
            type           => "string",
            label          => "Journal title",
            ill            => "title",
            api_max_length => 255,
            position       => 0
        },
        atitle => {
            exclude        => 1,
            type           => "string",
            label          => "Article title",
            ill            => "article_title",
            api_max_length => 255,
            position       => 1
        },
        article_title => {
            exclude        => 1,
            type           => "string",
            label          => "Article title",
            ill            => "article_title",
            api_max_length => 255,
            no_submit      => 1,
            position       => 1
        },
        aufirst => {
            type           => "string",
            label          => "Author's first name",
            ill            => "article_author",
            api_max_length => 50,
            position       => 2,
            join           => "aulast"
        },
        aulast => {
            type           => "string",
            label          => "Author's last name",
            api_max_length => 50,
            position       => 3
        },
        volume => {
            type           => "string",
            label          => "Volume number",
            ill            => "volume",
            api_max_length => 50,
            position       => 4
        },
        issue => {
            type           => "string",
            label          => "Journal issue number",
            ill            => "issue",
            api_max_length => 50,
            position       => 5
        },
        date => {
            type           => "string",
            ill            => "year",
            api_max_length => 50,
            position       => 7,
            label          => "Item publication date"
        },
        pages => {
            type           => "string",
            label          => "Pages in journal",
            ill            => "pages",
            api_max_length => 50,
            position       => 8
        },
        spage => {
            type           => "string",
            label          => "First page of article in journal",
            ill            => "spage",
            api_max_length => 50,
            position       => 8
        },
        epage => {
            type           => "string",
            label          => "Last page of article in journal",
            ill            => "epage",
            api_max_length => 50,
            position       => 9
        },
        doi => {
            type           => "string",
            label          => "DOI",
            ill            => "doi",
            api_max_length => 96,
            position       => 10
        },
        pubmedid => {
            type           => "string",
            label          => "PubMed ID",
            ill            => "pubmedid",
            api_max_length => 16,
            position       => 11
        },
        isbn => {
            type           => "string",
            label          => "ISBN",
            ill            => "isbn",
            api_max_length => 50,
            position       => 12
        },
        issn => {
            type           => "string",
            label          => "ISSN",
            ill            => "issn",
            api_max_length => 50,
            position       => 13
        },
        eissn => {
            type           => "string",
            label          => "EISSN",
            ill            => "eissn",
            api_max_length => 50,
            position       => 14
        },
        orderdateutc => {
            type      => "string",
            label     => "Order date UTC",
            exclude   => 1,
            no_submit => 1,
            position  => 99
        },
        statusdateutc => {
            type      => "string",
            label     => "Status date UTC",
            exclude   => 1,
            no_submit => 1,
            position  => 99
        },
        author => {
            type      => "string",
            label     => "Author",
            ill       => "author",
            exclude   => 1,
            no_submit => 1,
            position  => 99
        },
        year => {
            type      => "string",
            ill       => "year",
            exclude   => 1,
            label     => "Year",
            no_submit => 1,
            position  => 99
        },
        type => {
            type      => "string",
            ill       => "type",
            exclude   => 1,
            label     => "Type",
            no_submit => 1,
            position  => 99
        },
        lenderLibraryId => {
            type      => "string",
            exclude   => 1,
            label     => "Lender library ID",
            no_submit => 1,
            position  => 99
        },
        incdocs_type => {
            type      => "string",
            exclude   => 1,
            label     => "IncDocs type",
            no_submit => 1,
            position  => 99
        },
        customReference => {
            type      => "string",
            exclude   => 1,
            label     => "Custom reference",
            no_submit => 1,
            position  => 99
        },
        incdocs_id => {
            type      => "string",
            exclude   => 1,
            label     => "IncDocs ID",
            no_submit => 1,
            position  => 99
        },
        requesterLibraryId => {
            type      => "string",
            exclude   => 1,
            label     => "Requester library ID",
            no_submit => 1,
            position  => 99
        },
        requesterEmail => {
            type      => "string",
            exclude   => 1,
            label     => "Requester email",
            no_submit => 1,
            position  => 99
        },
        articleId => {
            type      => "string",
            exclude   => 1,
            label     => "Article ID",
            no_submit => 1,
            position  => 99
        },
        created => {
            type      => "string",
            exclude   => 1,
            label     => "IncDocs created",
            no_submit => 1,
            position  => 99
        },
        lastUpdated => {
            type      => "string",
            exclude   => 1,
            label     => "IncDocs last updated",
            no_submit => 1,
            position  => 99
        },
        libraryGroupId => {
            type      => "string",
            exclude   => 1,
            label     => "Library groupd ID",
            no_submit => 1,
            position  => 99
        }
    };
}

=head3 _validate_borrower

=cut

sub _validate_borrower {

    # Perform cardnumber search.  If no results, perform surname search.
    # Return ( 0, undef ), ( 1, $brw ) or ( n, $brws )
    my ( $input, $action ) = @_;

    return ( 0, undef ) if !$input || length $input == 0;

    my $patrons = Koha::Patrons->new;
    my ( $count, $brw );
    my $query = { cardnumber => $input };
    $query = { borrowernumber => $input } if ( $action && $action eq 'search_results' );

    my $brws = $patrons->search($query);
    $count = $brws->count;
    my @criteria = qw/ surname userid firstname end /;
    while ( $count == 0 ) {
        my $criterium = shift @criteria;
        return ( 0, undef ) if ( "end" eq $criterium );
        $brws  = $patrons->search( { $criterium => $input } );
        $count = $brws->count;
    }
    if ( $count == 1 ) {
        $brw = $brws->next;
    } else {
        $brw = $brws;    # found multiple results
    }
    return ( $count, $brw );
}

=head3 _logger

    my $logger = $backend->_logger($logger);
    my $logger = $backend->_logger;
    Getter/Setter for our Logger object.

=cut

sub _logger {
    my ( $self, $logger ) = @_;
    $self->{_logger} = $logger if ($logger);
    return $self->{_logger};
}

=head3 tool

=cut

sub tool {
    my ( $self, $args ) = @_;

    $self->tool_step1();
}

sub tool_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'tool-step1.tt' } );

    my $incdocs =
        Koha::Plugin::Com::PTFSEurope::IncDocs->new->new_ill_backend( { logger => Koha::ILL::Request::Logger->new } );
    my $response = $incdocs->{_api}->Libraries();

    if ( $response->{status} && $response->{error} ) {
        $template->param( 'error' => $response->{error} . ' - ' . $response->{error_description} );
        $self->output_html( $template->output() );
        return;
    }

    my $libraries = $response->{data};

    # iterate on libraries
    foreach my $incdocs_library (@$libraries) {
        my $patron = Koha::Patrons->search(
            [
                {
                    'extended_attributes.attribute' => { '=' => $incdocs_library->{id} },
                    'extended_attributes.code'      => $self->{config}->{patron_libraryidfield}
                },
            ],
            { 'prefetch' => ['extended_attributes'] }
        )->last;

        if ($patron) {
            $incdocs_library->{patron} = $patron;
        }

        my $additional_field =
            Koha::AdditionalFields->search(
            { name => $self->{config}->{library_libraryidfield}, tablename => 'branches' } )->next;

        my $library = Koha::Libraries->filter_by_additional_fields(
            [
                {
                    id    => $additional_field->id,
                    value => $incdocs_library->{id},
                },
            ]
        )->next;

        if ($library) {
            $incdocs_library->{library} = $library;
        }
    }

    $template->param( 'libraries' => $libraries );
    $self->output_html( $template->output() );
}

sub availability {
    my ( $self, $params ) = @_;

    my $response = { method => "confirm", stage => "availability" };

    my $request = $params->{request};

    my $incdocs =
        Koha::Plugin::Com::PTFSEurope::IncDocs->new->new_ill_backend( { logger => Koha::ILL::Request::Logger->new } );

    my $metadata = {
        branchcode => $params->{request}->branchcode,
        ( $params->{request}->extended_attributes->find( { type => 'doi' } ) )
        ? ( doi => $params->{request}->extended_attributes->find( { type => 'doi' } )->value )
        : (),
        ( $params->{request}->extended_attributes->find( { type => 'pubmedid' } ) )
        ? ( pubmedid => $params->{request}->extended_attributes->find( { type => 'pubmedid' } )->value )
        : (),
    };

    $metadata = Koha::ILL::Request::Workflow->new->prep_metadata($metadata);

    my $result = $incdocs->{_api}->Backend_Availability( { metadata => $metadata } );

    $response->{backend_availability} = $result;
    $response->{future}               = "commit";
    $response->{illrequest_id}        = $request->illrequest_id;

    return $response;
}

1;
