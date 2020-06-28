package V3_26;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'Media';

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();

    # add CDN specific fields
    $dbh->do('ALTER TABLE site ADD COLUMN cdn_url VARCHAR(255) AFTER `creation_date`');
    $dbh->do('ALTER TABLE media ADD COLUMN cdn_enabled BOOL NOT NULL DEFAULT 0 AFTER `full_text`');
}

sub per_installation {
    my ($self, %args) = @_;

    # nothing to do yet
}

1;
