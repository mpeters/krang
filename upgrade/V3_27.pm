package V3_27;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'Media';

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh(ignore_version => 1);

    $dbh->do('ALTER TABLE group_permission ADD COLUMN may_skip_related_assets BOOL NOT NULL DEFAULT 0');
}

sub per_installation {
    my ($self, %args) = @_;

    # nothing to do yet
}

1;
