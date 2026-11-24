package Koha::Plugin::Com::PTFSEurope::IncDocs::BackgroundJob::ReRequest;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Try::Tiny qw( catch try );

use Koha::ILL::Request::Logger;
use Koha::ILL::Requests;

use base 'Koha::BackgroundJob';

=head1 NAME

Koha::Plugin::Com::PTFSEurope::IncDocs::BackgroundJob::ReRequest - Request a declined IncDocs request again

=head1 API

=head2 Class methods

=head3 job_type

=cut

sub job_type {
    return 'plugin_incdocs_rerequest';
}

=head3 process

Request the declined ILL request again from another IncDocs library, the same way an unmediated
request is placed.

=cut

sub process {
    my ( $self, $args ) = @_;

    $self->start;

    my $request = Koha::ILL::Requests->find( $args->{illrequest_id} );
    my @messages;

    if ( $request && $request->status eq 'REQREV' ) {
        try {
            require Koha::Plugin::Com::PTFSEurope::IncDocs;
            Koha::Plugin::Com::PTFSEurope::IncDocs->new->new_ill_backend(
                { logger => Koha::ILL::Request::Logger->new } )
                ->unmediated_confirm( { request => $request, other => {} } );
            $request->discard_changes;

            my $lender = $request->extended_attributes->find( { type => 'lenderLibraryName' } )
                // $request->extended_attributes->find( { type => 'lenderLibraryId' } );
            if ( $request->status eq 'REQ' ) {
                $request->append_to_note(
                    sprintf(
                        'Automatically re-requested from IncDocs library %s (%d of %d)',
                        $lender ? $lender->value : '', $args->{attempt}, $args->{max}
                    )
                );
            } elsif ( $request->status eq 'UNAVAILABLE' ) {
                $request->append_to_note('Automatic re-request: not found at any other IncDocs library');
            } elsif ( $request->status eq 'ERROR' ) {
                $request->append_to_note(
                    sprintf(
                        'Automatic re-request (%d of %d) failed, see the error above', $args->{attempt},
                        $args->{max}
                    )
                );
            }
            push @messages, { type => 'success', code => 'status', status => $request->status };
        } catch {
            $request->append_to_note("Automatic re-request failed: $_");
            push @messages, { type => 'error', code => 'failed', error => "$_" };
        };
    } else {
        push @messages, { type => 'warning', code => 'skipped' };
    }

    $self->step;
    $self->finish( { messages => \@messages, illrequest_id => $args->{illrequest_id} } );
}

=head3 enqueue

    Koha::Plugin::Com::PTFSEurope::IncDocs::BackgroundJob::ReRequest->new->enqueue(
        { illrequest_id => $illrequest_id, attempt => 1, max => 3 } );

=cut

sub enqueue {
    my ( $self, $args ) = @_;

    $self->SUPER::enqueue(
        {
            job_size  => 1,
            job_args  => { map { $_ => $args->{$_} } qw( illrequest_id attempt max ) },
            job_queue => 'default',
        }
    );
}

1;
