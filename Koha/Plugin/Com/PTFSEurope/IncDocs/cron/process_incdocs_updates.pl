#!/usr/bin/perl

# This file is part of Koha.
#
# Copyright (C) 2025 PTFS Europe
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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use Getopt::Long qw( GetOptions );

use Koha::Script;
use Koha::ILL::Requests;
use Koha::Plugin::Com::PTFSEurope::IncDocs;

# Command line option values
my $get_help = 0;
my $debug    = 0;

my $options = GetOptions(
    'h|help' => \$get_help,
    'debug'  => \$debug,
);

if ($get_help) {
    get_help();
    exit 1;
}

my $incdocs = Koha::Plugin::Com::PTFSEurope::IncDocs->new();
if ( !$incdocs || !$incdocs->is_enabled ) {
    print "Koha::Plugin::Com::PTFSEurope::IncDocs plugin is not installed or not enabled. Exiting.\n";
    exit 0;
}

debug_msg("IncDocs backend installed and enabled");

my $requests = Koha::ILL::Requests->search( { backend => 'IncDocs', status => 'REQ' } );
my $count    = 0;
while ( my $request = $requests->next ) {
    $count++;
    my $incdocs_status =
        $incdocs->status( { request => $request, other => { illrequest_id => $request->illrequest_id } } );
    debug_msg( "Processing request: "
            . $request->illrequest_id
            . ". Indocs status is '"
            . $incdocs_status->{value}->{status}
            . "'" );

}
debug_msg("Processed $count requests");

sub debug_msg {
    my ($msg) = @_;

    if ( !$debug ) {
        return;
    }

    if ( ref $msg eq 'HASH' ) {
        use Data::Dumper;
        $msg = Dumper $msg;
    }
    print STDERR "$msg\n";
}

sub get_help {
    print <<"HELP";
$0: Process backend-wide ILL processors

This script will query IncDocs for request status updates and update
them in Koha accordingly.

Parameters:
    --debug                              print additional debugging info during run
    --help or -h                         get help
HELP
}
