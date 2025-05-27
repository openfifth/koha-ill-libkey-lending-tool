package Koha::Plugin::Com::PTFSEurope::IncDocs::Api;

use Modern::Perl;
use strict;
use warnings;

use JSON         qw( decode_json encode_json );
use URI::Escape  qw ( uri_unescape );
use MIME::Base64 qw( decode_base64 );

use Mojo::Base 'Mojolicious::Controller';
use Koha::Plugin::Com::PTFSEurope::IncDocs;

=head3 Libraries

Make a call to /libraries

=cut

sub Libraries {
    my $c = shift->openapi->valid_input or return;

    my $response = _make_request( 'GET', 'libraries' );

    if ( !defined $response ) {
        return $c->render(
            status  => 500,
            openapi => {
                status            => '500',
                error             => 'Plugin configuration',
                error_description => 'Invalid or missing. Please check.',
            }
        );
    } elsif ( $response->{data} ) {
        return $c->render(
            status  => 200,
            openapi => { data => $response->{data} }
        );
    } else {
        return $c->render(
            status  => 500,
            openapi => {
                status            => $response->{status},
                error             => $response->{error},
                error_description => $response->{error_description},
            }
        );
    }
}

sub Backend_Availability {
    my $c = shift->openapi->valid_input or return;

    my $config = _get_plugin_config();
    unless ( $config->{library_libraryidfield} ) {
        return $c->render(
            status  => 400,
            openapi => {
                error => 'Missing plugin configuration: Library id field not configured.',
            }
        );
    }

    my $metadata = $c->validation->param('metadata') || '';
    $metadata = decode_json( decode_base64( uri_unescape($metadata) ) );
    unless ( $metadata->{doi} || $metadata->{pubmedid} ) {
        return $c->render(
            status  => 400,
            openapi => {
                error => 'No doi or pubmedid provided',
            }
        );
    }

    my $library = Koha::Libraries->find( $metadata->{branchcode} );
    my $additional_field =
        Koha::AdditionalFields->search( { name => $config->{library_libraryidfield}, tablename => 'branches' } )->next;

    unless ($additional_field) {
        return $c->render(
            status  => 400,
            openapi => {
                      error => 'Configured additional field '
                    . $config->{library_libraryidfield}
                    . ' does not exist for libraries'
            }
        );
    }

    my $incdocs_id = $library->additional_field_values->search(
        { 'record_id' => $library->id, 'field_id' => $additional_field->id } )->next;

    unless ($incdocs_id) {
        return $c->render(
            status  => 400,
            openapi => {
                error => 'Destination library ' . $library->branchname . ' does not have a value for ' . $additional_field->name,
            }
        );
    }

    my $id_code  = $metadata->{doi} ? 'doi'            : 'pmid';
    my $id_value = $metadata->{doi} ? $metadata->{doi} =~ s/^\s+|\s+$//gr : $metadata->{pubmedid} =~ s/^\s+|\s+$//gr;

    if ( $id_code eq 'doi' ) {
        $id_value =~ s/.*?(?=10\.)//;
    }

    my $response =
        _make_request( 'GET', 'libraries/' . $incdocs_id->value . '/articles/' . $id_code . '/' . $id_value );

    if ( $response->{error} && grep { $_->{status} == 404 } @{ $response->{error} } ) {
        return $c->render(
            status  => 404,
            openapi => {
                error => 'Provided doi or pubmedid is not available in IncDocs',
            }
        );
    }

    if ( $response && ref $response->{data} eq 'HASH' && $response->{data}->{illLibraryName} ) {
        return $c->render(
            status  => 200,
            openapi => {
                response => $response,
                success  => "Found at another library",
            }
        );
    } elsif ( $response && ref $response->{data} eq 'HASH' && !$response->{data}->{illLibraryName} ) {
        return $c->render(
            status  => 200,
            openapi => {
                response => $response,
                success  => "Found locally",
            }
        );
    }
}

sub Create_Fulfillment_Request {
    my $c = shift->openapi->valid_input or return;

    my $data = $c->validation->param('body') || '';

    my $response = _make_request( 'POST', 'fulfillmentRequests', { data => $data } );

    if ( $response->{data} ) {
        return $c->render(
            status  => 200,
            openapi => $response->{data}
        );
    } elsif ( $response->{errors} ) {
        return $c->render(
            status  => 400,
            openapi => {
                error => $response->{errors},
            }
        );
    } elsif ( $response->{error} ) {
        return $c->render(
            status  => 400,
            openapi => {
                error => $response->{error},
            }
        );
    } else {
        return $c->render(
            status  => 400,
            openapi => {
                error => $response->{data},
            }
        );
    }
}

sub Fulfillment_Request_Status {
    my $c = shift->openapi->valid_input or return;

    my $fulfillment_request_id = $c->validation->param('fulfillment_request_id') || '';

    my $response = _make_request( 'GET', 'fulfillmentRequests/' . $fulfillment_request_id );

    if ( $response->{data} ) {
        return $c->render(
            status  => 200,
            openapi => $response->{data}
        );
    } elsif ( $response->{error} ) {
        return $c->render(
            status  => 400,
            openapi => {
                error => $response->{error},
            }
        );
    } else {
        return $c->render(
            status  => 400,
            openapi => {
                error => $response->{data},
            }
        );
    }
}

=head3 _make_request

Make a request to the LibKey Lending Tool API. If the request is not for /auth/login, it will automatically call
Authenticate before making the request.

=cut

sub _make_request {
    my ( $method, $endpoint_url, $payload ) = @_;

    my $config = _get_plugin_config();
    return undef unless $config;

    my $incdocs_api_url = 'https://lendingtool-api.thirdiron.com/public/v1/libraryGroups';
    my $access_token    = $config->{access_token};
    my $library_group   = $config->{library_group};

    my $uri =
        URI->new( $incdocs_api_url . '/' . $library_group . '/' . $endpoint_url . '?access_token=' . $access_token );

    my $request = HTTP::Request->new( $method, $uri, undef, undef );
    if ($payload) {
        $request->header( 'Content-Type' => 'application/json; charset=UTF-8' );
        $request->content( encode_json($payload) );
    }
    my $ua       = LWP::UserAgent->new;
    my $response = $ua->request($request);

    if ( $response->code == 404 ) {
        return {
            error => [
                {
                    status => $response->code,
                    title  => $response->message,
                }
            ],
        };
    }

    return decode_json( $response->decoded_content );
}

sub _get_plugin_config {
    my $plugin = Koha::Plugin::Com::PTFSEurope::IncDocs->new();
    my $config = $plugin->retrieve_data("incdocs_config");
    return decode_json($config) if $config;
    return {};
}

1;
