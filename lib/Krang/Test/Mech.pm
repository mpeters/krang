package Krang::Test::Mech;
use strict;
use warnings;
use base 'Test::WWW::Mechanize';
use Krang::ClassLoader Message => qw(get_message_text);
use Krang::ClassLoader Conf    => qw(KrangRoot HostName ApachePort EnableSSL SSLApachePort);
use File::Spec::Functions qw(catfile);
use Params::Validate qw(validate);
use Carp qw(carp);
use URI;

=head1 NAME

Krang::Test::Mech - Test::WWW::Mechanize subclass with Krang specific helper methods

=head1 DESCRIPTION

This class is a very simple wrapper around L<Test::WWW::Mechanize> that provides
some simple constructs that are useful when writing Krang web tests.

=head1 SYNOPSIS

    use Krang::Test::Mech;
    my $mech = Krang::Test::Mech->new();
    ...
    $mech->contains_message('email_missing', pkg('User'));
    $mech->lacks_message('email_missing', pkg('User'));

    $mech->login(username => $name, password => $password);

=head1 INTERFACE

=over

=item C<< new([ %args ]) >>

Returns a new Krang::Test::Mech object with the following values
values set in the L<Test::WWW::Mechanize> constructor:

=over

=item C<< autocheck => 1 >>

=item C<< agent => 'Linux Mozilla' >>

=back

Any additional arguments will be passed on directly to the L<Test::WWW::Mechanize>
constructor.

=cut

sub new {
    my ($class, %args) = @_;
    my $agent = delete $args{agent} || 'Linux Mozilla';
    my $self = $class->SUPER::new(
        autocheck   => 1,
        stack_depth => 1,
        %args,
    );
    $self->agent_alias($agent);
    bless($self, $class);
}

=back 

=head2 OBJECT METHODS

=over

=item C<< contains_message($key, $class [, %args ]) >>

Prints an OK test message if the current page contains the matching message from
L<Krang::Message> given the C<$key> and the C<$class>. Else print NOT OK.
If the message requires variable substitution, they can be provided
by passing in extra C<%args>.

In the case where you don't know what the actual value of a message variable
will be, you can pass a regular expression instead.

    $mech->contains_message('reverted_story', 'Krang::CGI::Story',
        version => qr/\d+/);

=cut

sub contains_message {
    my ($self, $key, $class, %args) = @_;
    my $text = $self->_get_message_text($key, $class, \%args);
    if (!defined $text) {
        carp "No such message '$key' in class '$class'";
    }

    # up the level of the test so error messages contain the line
    # number of the user of this method, not our use of
    # content_contains()
    {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        if( ref $text eq 'Regexp' ) {
            $self->content_like($text, "contains message $key");
        } else {
            $self->content_contains($text, "contains message $key");
        }
    }
}

sub _get_message_text {
    my ($self, $key, $class, $args) = @_;
    my (%msg_vars, %regex_vars);
    
    foreach my $k (keys %$args) {
        my $val = $args->{$k};
        if( ref $val eq 'Regexp' ) {
            $msg_vars{$k} = "__Regexp__${k}__";
            $regex_vars{$k} = $val;
        } else {
            $msg_vars{$k} = $val;
        }
    }

    # get the actual text from Krang::Message
    my $text = get_message_text($key, $class, %msg_vars);
    if( $text ) {
        # since the messages are JS encoded in the template, we need to
        # do the same here
        $text =~ s/\\/\\\\/g;
        $text =~ s/'/\\'/g;
        $text =~ s/"/\\"/g;
        $text =~ s/\n/\\n/g;
        $text =~ s/\r/\\r/g;

        # now replace our regexp markers with the real thing
        if( %regex_vars ) {
            $text = quotemeta($text);
            foreach my $k (keys %regex_vars) {
                $text =~ /(.*)(__Regexp__${k}__)(.*)/;
                $text = $1 . $regex_vars{$k} . $3;
            }
            return qr/$text/;
        }
    }
    return $text;
}

=item C<< lacks_message($key, $class [, %args ]) >>

Prints an OK test message if the current page lacks the matching message from
C<data/messages.conf> given the C<$key> and the C<$class>. Else print NOT OK
If the message requires variable substitution, they can be provided
by passing in extra C<%args>.

=cut

sub lacks_message {
    my ($self, $key, $class, %args) = @_;
    my $text = $self->_get_message_text($key, $class, \%args);
    if (!defined $text) {
        carp "No such message '$key' in class '$class'";
    }

    # up the level of the test so error messages contain the line
    # number of the user of this method, not our use of
    # content_contains()
    {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        if( ref $text eq 'Regexp' ) {
            $self->content_unlike($text, "contains message $key");
        } else {
            $self->content_lacks($text, "contains message $key");
        }
    }
}

=item C<< login(username => $user, password => $password) >>

Creates a login form and logs in this mech with the given the username and password.
If a username and password are not provided then we will use the C<KRANG_USERNAME>
and C<KRANG_PASSWORD> environment variables.

=cut

sub login {
    my $self = shift;
    my %args = validate(@_, { username => 1, password => 1 });
    my $user = exists $args{username} ? $args{username} : $ENV{KRANG_USERNAME};
    my $pw   = exists $args{password} ? $args{password} : $ENV{KRANG_PASSWORD};

    $self->get($self->script_url('login.pl'));
    $self->submit_form(
        form_name => 'form-login',
        fields    => {
            username => $user, 
            password => $pw,
        },
    );
    $self->submit();
}

=item C<< change_hiddens() >>

L<WWW::Mechanize> will not allow you to change hidden field values by
default. If we need to test hidden values in our forms, we can use
this function to set all hidden value read only attributes to 0,
permitting the changing of its value in our mech tests.

=cut

sub change_hiddens {
    my $self = shift;
    foreach my $form ($self->forms()) {
        map { $_->readonly(0) } $form->inputs();
    }
    return 1;
}

=back

=head2 CLASS METHODS

=over

=item C<< script_url($script_name) >>

Returns the full URL to access the given script taking into account
the current C<KRANG_INSTANCE>.

    my $url = Krang::Test::Mech->script_url('login.pl');

=cut

sub script_url {
    my ($pkg, $path) = @_;

    my $uri = URI->new();
    $uri->scheme(EnableSSL ? 'https' : 'http');
    $uri->host(HostName . ':' . (EnableSSL ? SSLApachePort : ApachePort));

    # if we have a script add it to the instance, else use the instance
    $path = $path ? catfile($ENV{KRANG_INSTANCE}, $path) : $ENV{KRANG_INSTANCE};
    $uri->path($path);

    return $uri->as_string;
}


=back

=cut

1;
