package Krang::Handler;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::Handler - Krang mod_perl handler

=head1 SYNOPSIS

None.  See F<conf/httpd.conf.tmpl> for usage.

=head1 DESCRIPTION

This module handles Apache requests for Krang.  It contains all the
Apache/mod_perl handlers used by Krang.

The basic order of events is:

=over 4

=item Krang::Handler->trans_handler

Responsible for setting Krang instance name and propagating it
to the environment (KRANG_INSTANCE).  Responsible for re-writing
requests internally to properly locate files in the case of
"root"-flavor requests.  E.g.:

Both requests:

  http://my-krang/instance1/someasset.gif
  http://my-krang/someasset.gif

 ...translate to...

  /path/to/document/root/someasset.gif

=item Krang::Handler->access_handler

Access Control.  Checks to make sure the user has a browser that will
work with Krang.

=item Krang::Handler->authen_handler

Authentication.  Checks for an auth cookie.  If found and valid, the request is 
associated with the user_id via the $request->connection->user() 
method.  The effect of this is that $query->remote_user() and 
$ENV{REMOTE_USER} will properly report the user who is logged in.

=item Krang::Handler->authz_handler

Authorization. Enforces "require valid-user" only.  IOW, 
if a user is specified, they are authorized.  If no user
has been specified (via the authen_handler), the request is
redirected to the login application.

Also, if C<PasswordChangeTime> is set to a non-zero value,
we check to see if the user's C<force_pw_change> has been
set. If it has, the user is redirected to C<force_pw_change>
runmode of the C<CGI::MyPref> class.

=item Krang::Handler->log_handler

Logging.  When the application is running under Apache::Registry (not
in CGI_MODE) this handler gets error messages out of
C<< $r->notes() >> and logs them with Krang::Log.

=back


=cut

use Apache::Constants qw(:response);
use Apache::Cookie;
use Apache::SizeLimit;
use Apache::URI;
use Apache;
use CGI ();
use Carp qw(croak);
use Digest::MD5 qw(md5_hex md5);
use File::Spec::Functions qw(splitdir rel2abs catdir catfile);
use HTTP::BrowserDetect;
use Krang::Cache;
use Krang::ClassLoader 'CGI::Login';
use Krang::ClassLoader 'ErrorHandler';
use Krang::ClassLoader 'File';
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader Conf =>
  qw(KrangRoot PasswordChangeTime ApacheMaxSize Secret ApacheMaxUnsharedSize ForceStaticBrowserCaching DefaultLanguage);
use Krang::ClassLoader Log => qw(critical info debug);
use Krang::ClassLoader 'AddOn';
use Krang;
use Krang::ClassLoader 'Session' => qw(%session);

BEGIN { pkg('AddOn')->call_handler('InitHandler') }

if (ApacheMaxSize) {
    Apache::SizeLimit->set_max_process_size(ApacheMaxSize);
} elsif (!defined ApacheMaxSize) {
    Apache::SizeLimit->set_max_process_size(64000);    # 64MB by default
}
Apache::SizeLimit->set_max_unshared_size(ApacheMaxUnsharedSize) if ApacheMaxUnsharedSize;

##########################
####  PUBLIC METHODS  ####
##########################

=head1 INTERFACE

Following are methods which can be overridden in sub-classes.

=over 4

=item unprotected_uri()

Return a list of URIs which should never be restricted by login.

=cut

sub unprotected_uri {
    my $self = shift;

    # Just the login.pl, by default
    my @uris = ($self->login_uri);

    return @uris;
}

=item login_uri()

The URI to which users should be redirected if they fail authorization.

=cut

sub login_uri {
    my $self = shift;

    return qw(login.pl);
}

=pod

=back

=cut

# Re-write the incoming request, based on Krang Instance rules:
#
# flavor == "instance" :  Instance name should be set, or die()
# flavor == "root"     :  If no instance name, must be in root directory.  Show list of instances.
#                      :  If we have an instance name, it should match first directory in path
#                      :  If in instance path, rewrite uri to point to real assets in htdocs root.
#
sub trans_handler ($$) {
    my $self = shift;
    my ($r)  = @_;
    my $uri  = $r->uri;

    # if it's a request for a /static file then strip off the static
    # prefix that looks like "/static/XXXX" where "XXXX" is the install_id
    if ($uri =~ /^\/static\//) {

        # if we have it configured to do so
        if (ForceStaticBrowserCaching) {

            # make it expire waaaaay in the future
            $r->err_header_out('Expires'       => 'Mon, 28 Jul 2014 23:30:00 GMT');
            $r->err_header_out('Cache-Control' => 'max-age=315360000');
        }

        # find the appropriate krang file
        $uri =~ s{^/static/[^/]+/}{/};
        my $file = pkg('File')->find("htdocs/$uri");
        $r->filename($file);
        return OK;
    }

    return OK if $r->prev && $r->prev->uri =~ /^\/static\//;

    # Only handle main requests, unless this is a request for bug.pl
    # which happens on redirects from ISEs
    unless ($r->is_initial_req() or $uri =~ /\/bug\.cgi/) {
        return DECLINED;
    }

    # Read directory configuration for this request
    my $instance_name = $r->dir_config('instance');
    $instance_name = '' unless (defined($instance_name));
    my $flavor = $r->dir_config('flavor');

    # Are we in the context of an Instance server?
    if ($flavor eq 'instance') {
        unless (length($instance_name)) {
            my $error = "No instance name set for this Krang instance";
            critical($error);
            die($error);
        }

        # Set current instance, or die trying
        debug("Krang::Handler:  Setting instance to '$instance_name'");
        pkg('Conf')->instance($instance_name);

        # Propagate the instance name to the CGI-land
        $r->cgi_env('KRANG_INSTANCE' => $instance_name);

        # Handle DirectoryIndex case...
        $uri .= 'workspace.pl' if ($uri =~ /\/$/);

        # now map to a file on disk with Krang::File
        my $file = pkg('File')->find("htdocs/$uri");
        $r->filename($file);
        return OK;
    }

    ## We're now in the context of a "root"-flavored instance... directory city, baby.
    if (length($instance_name)) {

        # We have an instance name.  We should be in a matching path
        unless ($uri =~ /^\/$instance_name/) {
            my $error = "Expected uri like '/$instance_name\*', got '$uri' instead";
            critical($error);
            die($error);
        }

        # Set current instance, or die trying
        debug("Krang::Handler:  Setting instance to '$instance_name'");
        pkg('Conf')->instance($instance_name);

        # Propagate the instance name to the CGI-land
        $r->cgi_env('KRANG_INSTANCE' => $instance_name);

        # Rewrite the current uri to send request back to the real assets in the root
        my $new_uri = $uri;
        $new_uri =~ s/^\/$instance_name//;

        # Handle root case: workspace.pl
        $new_uri = "/workspace.pl" if (($new_uri eq '/') || $new_uri eq '');

        # map to filename on disk
        my $fq_filename = pkg('File')->find("htdocs/$new_uri");
        $r->filename($fq_filename);

        return OK;

    } else {

        # allow xinha requests through
        if ($uri =~ /xinha/i) {
            my $filename = pkg('File')->find("htdocs/$uri");
            if ($filename) {
                $r->filename($filename);
                return OK;
            }
        }

        # allow requests for static files through if they're present
        if ($uri =~ /\.(css|js|jpg|gif|png|js|html)$/i) {
            my $filename = pkg('File')->find("htdocs/$uri");
            if ($filename) {
                $r->filename($filename);
                return OK;
            }
        }

        # stop other requests unless they're for the root
        return FORBIDDEN unless ($uri eq '/');

        # We're looking at the root.  Set handler to show list of instances
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&instance_menu);

        return DECLINED;

    }
}

# Check the browser using HTTP::BrowserDetect and bounce old browsers
# before they can get into trouble.
sub access_handler ($$) {
    my $self = shift;
    my ($r) = @_;

    my %allow_browsers = (
        netscape  => 7.1,
        ie        => 6,
        mozilla   => 5,
        firefox   => 1.5,
        safari    => 1.3,
        konqueror => 1,
    );

    my %engine_of = (
        netscape  => 'Gecko',
        mozilla   => 'Gecko',
        firefox   => 'Gecko',
        ie        => 'IE',
        safari    => 'WebKit',
        konqueror => 'WebKit',
    );

    my $bd = HTTP::BrowserDetect->new($r->header_in('User-Agent'));
    foreach my $browser (keys %allow_browsers) {
        if ($bd->$browser) {
            $allow_browsers{$browser} =~ /(\d)+(\.\d+)?/;
            my ($major, $minor) = ($1, $2);
            $minor ||= ".0";
            if ($bd->major > $major
                or ($bd->major == $major && $bd->minor >= $minor))
            {
                $r->cgi_env("KRANG_BROWSER_ENGINE" => $engine_of{$browser});
                return OK;
            }
        }
    }

    # failure
    debug("Unsupported browser detected: " . $r->header_in('User-Agent'));
    $r->custom_response(FORBIDDEN,
        "<h1>Unsupported browser detected.</h1><p>This application requires Firefox 1.5+, Safari 1.3+, Internet Explorer 6+, Mozilla 1.7+, Netscape 7+ or Konqueror 1+.</p>"
    );
    return FORBIDDEN;
}

# Attempt to retrieve user identity from session cookie.
# Set REMOTE_USER and KRANG_SESSION_ID if successful.
sub authen_handler ($$) {
    my $self = shift;
    my ($r) = @_;

    # If the request (or redirected request) was for a static item, let it through
    return OK if $r->uri =~ /^\/static\// or ($r->prev && $r->prev->uri =~ /^\/static\//);

    # Only handle main requests, unless request is for bug.pl (which happens on ISE redirects)
    return DECLINED unless $r->is_initial_req() or $r->uri =~ /\/bug\.cgi/;

    # Get Krang instance name
    my $instance = pkg('Conf')->instance();

    # Get cookies
    my %cookies = Apache::Cookie->new($r)->parse;

    # If there's no ID or no session cookie, redirect to Login
    unless ($cookies{$instance}) {

        # no cookie, redirect to login
        debug("No cookie found, passing Authen without user login");
        return OK;
    }

    # Validate authen cookie
    my %cookie     = $cookies{$instance}->value;
    my $session_id = $cookie{session_id};
    my $hash       = md5_hex($cookie{user_id} . $cookie{instance} . $session_id . Secret());
    if ($cookie{hash} ne $hash or $cookie{instance} ne pkg('Conf')->instance()) {

        # invalid cookie, send to login
        critical("Invalid cookie found, possible breakin attempt from IP "
              . $r->connection->remote_ip
              . ".  Passing Authen without user login.");
        return OK;
    }

 # A non-PERL request (e.g. image), bug, or help file: let it through (we are already authenticated)
    if ($r->uri !~ /(\.pl|\/|$instance)$/ || $r->uri =~ /\/bug\.cgi$/ || $r->uri =~ /\/help\.pl$/) {

        # We are authenticated:  Setup REMOTE_USER
        $r->connection->user($cookie{user_id});
        return OK;
    }

    # This section needs some clarification. A Krang user can have multiple windows open at
    # the same time. Each window has it's own session so that we don't stomp over what's going
    # on in another window. So we store the window-id/session-id mapping in the instance cookie.
    # But since a cookie can only hold 4096 bytes we need to make sure we never get bigger than
    # that or strange things can happen. To do this we need to do a Least-Recently-Used (LRU) list.
    # So we store the timestamp (in epoch seconds) for each window/session pair as well.
    # Here's the math we're using:
    # 4000 bytes total (minus 96 to deal with the original session_id, user_id and instance name)
    # 42 bytes for each window/session mapping (32 bytes for the session_id and 10 for the label)
    # 20 bytes for each window/timestamp mapping (10 bytes for the timestamp and 10 for the label)
    # 62 bytes per window
    # 64 active windows max
    my $max_active_windows = 64;

    # Get window_id from query
    my %args = $r->args();
    my $window_id = $args{window_id} || '';

    # Get session_id for window_id
    if ($window_id) {

        # existing window
        $session_id = $cookie{"wid_$window_id"};

        # if there's no $session_id for this window, logout happened in other window
        undef $window_id unless $session_id;
    }

    # No window ID means no session for this window: create a new one
    unless ($window_id) {

        # new window ID
        $window_id = $cookie{next_wid}++;

        # new session
        $session_id = pkg('Session')->create();

        # store mapping between new window ID and new session ID in cookie
        $cookie{"wid_$window_id"} = $session_id;

        # put language pref in new session
        $session{language} = pkg('MyPref')->get('language', $cookie{user_id})
          || DefaultLanguage
          || 'en';

        # if there are more than $max_active_windows windows then we need to get rid
        # of the LRU
        if (keys %cookie > $max_active_windows) {
            info("Too many window/session combinations.");
            my @ids = grep { $_ =~ /^wid_/ } keys %cookie;
            @ids = map { $_ =~ /^wid_(\d+)/; $1; } @ids;
            @ids = sort { ($cookie{"wts_$a"} || 0) <=> ($cookie{"wts_$b"} || 0) } @ids;
            my $lru = $ids[0];

            # remove the session and the data about it in the cookie
            my $lru_session_id = delete $cookie{"wid_$lru"};
            pkg('Session')->delete($lru_session_id);
            delete $cookie{"wts_$lru"};
            info("Deleted LRU window #$lru");
        }
    }

    # update the timestamp on the window/session combo
    $cookie{"wts_$window_id"} = time;

    # the window/session mapping cookie has changed, so update the client
    $cookies{$instance}->value([%cookie]);
    Apache::Cookie->new($r, -name => $instance, -value => \%cookie, -path => '/')->bake;

    # Check for invalid session
    unless (pkg('Session')->validate($session_id)) {
        debug("Invalid session '$session_id' for window $window_id. Wiping its cookie.");
        return OK;
    }

    # We have a valid session/user!  Setup REMOTE_USER
    $r->connection->user($cookie{user_id});

    # Propagate user & window to CGI-land via the environment
    $r->cgi_env('KRANG_SESSION_ID' => $session_id);
    $r->cgi_env('KRANG_WINDOW_ID'  => $window_id);

    # We are authenticated, we've got a window_id and a valid session:
    # Redirect to workspace if user typed a login URI in a new window
    my $login_uri = $self->login_uri;
    if ($r->uri =~ m!$login_uri!) {
        if (!$args{rm} || ($args{rm} && $args{rm} ne 'logout')) {
            return $self->_redirect_to_workspace($r, $instance, $window_id);
        }
    }
    pkg('Session')->unload();

    return OK;
}

# Authorization
sub authz_handler ($$) {
    my $self = shift;
    my ($r) = @_;

    # If the request (or redirected request) was for a static item, let it through
    return OK if $r->uri =~ /^\/static\// or ($r->prev && $r->prev->uri =~ /^\/static\//);

    # Only handle main requests, unless this is a request for bug.pl
    # which happens on redirects from ISEs
    return DECLINED unless $r->is_initial_req() or $r->uri =~ /\/bug\.cgi/;

    my $path     = $r->uri();
    my $instance = pkg('Conf')->instance();
    my $flavor   = $r->dir_config('flavor');

    # always allow access to the specified apps
    my @unprotected_uri = $self->unprotected_uri();
    foreach my $uu (@unprotected_uri) {
        if (   ($flavor eq 'root' and $path =~ m!^/$instance/$uu!)
            or ($flavor eq 'instance' and $path =~ m!^/$uu!))
        {
            return OK;
        }
    }

    # always allow access to the CSS file and images - needed before
    # login to display the login screen
    return OK
      if $path =~ m!krang_login$!
          or $path =~ m!\.(gif|jpg|jpeg|png|css|js|ico)$!;

    # If user is logged in
    if (my $user_id = $r->connection->user) {

        # if we are enforcing changes in pw and the user's not
        # already trying to change their pw
        if (PasswordChangeTime && $path !~ /my_pref\.pl/) {

            # check the last time the user changed their pw
            eval "require pkg('User')";
            my ($user) = pkg('User')->find(user_id => $user_id);
            if ($user->force_pw_change) {
                return $self->_redirect_to_change_pw($r, $flavor, $instance);
            } else {
                return OK;
            }
        } else {

            # if we're logged in, we're good
            return OK;
        }
    }

    # No user?  Not a request to login?  Redirect the user to login!
    return $self->_redirect_to_login($r, $flavor, $instance);
}

#############################
####  INTERNAL HANDLERS  ####
#############################

# display a menu of available instances
sub instance_menu {
    my ($r) = @_;

    # setup the instance loop
    my (@loop, @instances);
    @instances = pkg('Conf')->instances();

    # if there's only one instance, just go there
    if (scalar @instances == 1) {
        $r->headers_out->{Location} = '/' . $instances[0] . '/';
        return REDIRECT;

        # else, show the menu
    } else {
        my $template = pkg('HTMLTemplate')->new(
            filename => 'instance_menu.tmpl',
            cache    => 1
        );

        foreach my $instance (@instances) {
            pkg('Conf')->instance($instance);
            push(
                @loop,
                {
                    InstanceName        => $instance,
                    InstanceDisplayName => (pkg('Conf')->InstanceDisplayName || $instance),
                }
            );
        }
        $template->param(instance_loop => \@loop);

        # output HTML
        $r->send_http_header('text/html');
        print $template->output();
        return OK;
    }

}

sub log_handler ($$) {
    my $pkg = shift;
    my $r   = shift;

    # in Apache::Registry mode this is where we collect die() and
    # warn()s since they don't get caught by Krang::ErrorHandler
    if ($ENV{GATEWAY_INTERFACE} =~ /Perl/) {
        if (my $err = $r->notes('error-notes')) {
            critical($err);
        }
    }

    # must make sure the cache is off at the end of the request
    if (Krang::Cache::active()) {
        critical("Cache still on in log handler!  This cache was started at "
              . join(', ', @{$Krang::Cache::CACHE_STACK[-1]})
              . ".");
        Krang::Cache::stop() while (Krang::Cache::active());
    }

    return OK;
}

# the site-server transhandler maps requests to a site's preview or
# publish path
sub siteserver_trans_handler ($$) {
    my $self = shift;
    my ($r)  = @_;
    my $host = $r->hostname;
    my $port = $r->get_server_port;

    # add in port number if necessary
    $host .= ":$port" unless $port == 80;

    # find a site for this hostname, looking in all instances
    eval "require " . pkg('Site') or die $@;
    my $path;
  INSTANCE: foreach my $instance (pkg('Conf')->instances) {
        pkg('Conf')->instance($instance);
        my @sites = pkg('Site')->find();
        foreach my $site (@sites) {
            my $url         = $site->url;
            my $preview_url = $site->preview_url;

            # is it a match?
            if ($url eq $host) {
                $path = $site->publish_path;
                last INSTANCE;
            } elsif ($preview_url eq $host) {
                $path = $site->preview_path;
                last INSTANCE;
            }
        }
    }

    # Didn't find a site?  Null out doc root and forbid request
    unless ($path) {
        $r->document_root(catdir(KrangRoot, "tmp"));
        return FORBIDDEN;
    }

    # Set up DOCUMENT_ROOT
    $r->document_root($path);

    # map the URI to a filename
    my $filename = catfile($path, $r->uri);
    $r->filename($filename);
    return OK;
}

###########################
####  PRIVATE METHODS  ####
###########################

sub _redirect_to_login {
    my $self = shift;
    my ($r, $flavor, $instance) = @_;

    my $login_app = $self->login_uri();

    # for ajaxy redirect
    my %content = $r->content;
    if ($content{ajax}) {
        $login_app .= '?rm=redirect_to_login&ajax=1';
    }

    my $new_uri = ($flavor eq 'instance' ? "/$login_app" : "/$instance/$login_app");

    return $self->_do_redirect($r, $new_uri);
}

sub _redirect_to_workspace {
    my $self = shift;
    my ($r, $instance, $window_id) = @_;

    my $app = "workspace.pl?window_id=$window_id";
    my $new_uri = $r->dir_config('flavor') eq 'instance' ? "/$app" : "/$instance/$app";

    return $self->_do_redirect($r, $new_uri);
}

sub _redirect_to_change_pw {
    my $self = shift;
    my ($r, $flavor, $instance) = @_;

    my $app = 'my_pref.pl?rm=force_pw_change';
    my $new_uri = ($flavor eq 'instance' ? "/$app" : "/$instance/$app");

    return $self->_do_redirect($r, $new_uri);
}

sub _do_redirect {
    my $self = shift;
    my ($r, $new_uri) = @_;

    $r->err_header_out(Location => $new_uri);
    my $output = "Redirect: <a href=\"$new_uri\">$new_uri</a>";

    return REDIRECT;
}

1;
