package Koha::Plugin::Com::PTFSEurope::IncDocs::Api;

use Modern::Perl;
use strict;
use warnings;

use JSON         qw( decode_json );
use URI::Escape  qw ( uri_unescape );
use MIME::Base64 qw( decode_base64 );

use Mojo::Base 'Mojolicious::Controller';
use Koha::Plugin::Com::PTFSEurope::IncDocs;

=head3 Libraries

Make a call to /libraries

=cut

sub Libraries {
    my $c = shift->openapi->valid_input or return;

    return _make_request( 'GET', 'libraries' );
}

sub Backend_Availability {
    my $c = shift->openapi->valid_input or return;

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

    my $response = _make_request( 'GET', 'libraries/1814/articles/pmid/123' )
        ;    #local library_id / articles / pmig/doi/ [actual_value]

    if ($response) {
        return $c->render(
            status  => 200,
            openapi => {
                success => "At library: " . $response->{data}->{illLibraryName},
            }
        );
    } else {
        return $c->render(
            status  => 404,
            openapi => {
                error => 'Provided doi or pubmedid is not available in ReprintsDesk',
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

    my $plugin = Koha::Plugin::Com::PTFSEurope::IncDocs->new();
    my $config = decode_json( $plugin->retrieve_data("incdocs_config") || {} );

    my $incdocs_api_url = 'https://lendingtool-api.thirdiron.com/public/v1/libraryGroups';
    my $access_token    = $config->{access_token};
    my $library_group   = $config->{library_group};

    my $uri =
        URI->new( $incdocs_api_url . '/' . $library_group . '/' . $endpoint_url . '?access_token=' . $access_token );

    $payload->{access_token} = $access_token;
    $uri->query_form($payload);

    my $request  = HTTP::Request->new( $method, $uri, undef, undef );
    my $ua       = LWP::UserAgent->new;
    my $response = $ua->request($request);

    return decode_json( $response->decoded_content );
}

1;
