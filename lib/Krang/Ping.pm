package Krang::Ping;
use strict;
use warnings;

use Apache::Constants qw(:common);
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

=head1 NAME

Krang::Ping - A simple mod_perl handler to be used w/monitoring.

=head1 SYNOPSIS

  use  'Krang::Ping';

=head1 DESCRIPTION

This module will listen for ping requests sent via monitoring software.  It
will return a 200 OK and the text string 'ping'.

If a file is placed at F<KrangRoot/tmp/suspend_ping>, this handler will instead
return C<403 FORBIDDEN> to all requests.  The idea is to point a load balancer
at this URL and use this as a way to tell the load balancer to stop sending
requests to this server.

=head1 INTERFACE

None.

=cut

our $SUSPEND_FILE = catfile(KrangRoot, 'tmp', 'suspend_ping');

sub handler {
    my $r = shift;

    if (-e $SUSPEND_FILE) {
        return FORBIDDEN;
    }

    $r->send_http_header('text/plain');
    print "site ok\n";
    return OK;
}

1;
