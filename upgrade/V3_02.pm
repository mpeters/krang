package V3_02;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

sub per_installation {

}

sub per_instance {
    my $self = shift;
    my $dbh = dbh();

    # add 'archived' and 'trashed' columns to STORY
    $dbh->do('ALTER TABLE story ADD COLUMN archived BOOL NOT NULL');
    $dbh->do('ALTER TABLE story ADD COLUMN trashed  BOOL NOT NULL');

    # add admin permission 'admin_delete' and give it to admin and editor group
    $dbh->do('Alter TABLE group_permission ADD COLUMN admin_delete BOOL NOT NULL DEFAULT 0');
    $dbh->do('Update group_permission SET admin_delete = 1 WHERE group_id = 1');
    $dbh->do('Update group_permission SET admin_delete = 1 WHERE group_id = 2');
}

1;