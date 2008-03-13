use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader 'Script';

use Krang::ClassLoader 'Test::Content';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Media';

use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Template';

use Krang::ClassLoader Conf => qw(InstanceElementSet);

use Test::More qw(no_plan);

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

BEGIN {
    use_ok(pkg('Category'));
}

# Create site
my $site = pkg('Site')->new(
    preview_url  => 'category_copy_test.preview.com',
    url  => 'category_copy_test.com',
    preview_path => '/tmp/category_copy_preview',
    publish_path => '/tmp/category_copy_publish'
);
$site->save;
END {$site->delete}
isa_ok($site, 'Krang::Site');

# setup group with asset permissions
my $group = pkg('Group')->new(
			      name           => 'ForOtherUser',
			      asset_story    => 'edit',
			      asset_media    => 'edit',
			      asset_template => 'edit',
			     );
$group->save();
END { $group->delete }

# put a user into this group
my $user = pkg('User')->new(
			    login     => 'bob',
			    password  => 'bobspass',
			    group_ids => [$group->group_id],
			   );
$user->save();
END { $user->delete }

# some variables
my ($creator, $this, $that, $source, $water, $conflict);
my (@categories, @stories);

#
# 1. Test without conflict possibility
#
setup_tree();
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 0);
};
is(not($@), 1, "May copy test without conflicts");

#
# 2. Story conflict without overwrite
#
setup_tree();
$conflict = pkg('Story')->new(categories => [$that],
                                 slug       => 'from_story_1',
                                 class      => 'article',
                                 title      => 'Conflicting with \$from_story_1');
$conflict->save;
push @stories, $conflict;
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 0);
};
diag('Testing Story conflict without overwrite - should throw exception');
isa_ok($@, 'Krang::Category::CopyAssetConflict');

#
# 3. Story conflict with overwrite
#
setup_tree();
$conflict = pkg('Story')->new(categories => [$that],
                              slug       => 'from_story_1',
                              class      => 'article',
                              title      => 'Conflicting with \$from_story_1');
$conflict->save;
push @stories, $conflict;
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 1);
};
is(not($@), 1, 'Story conflict with overwrite');

#
# 4. Media conflict without overwrite
#
setup_tree();
# Add a TO category also existing in FROM
$source = pkg('Category')->new(parent_id => $that->category_id,
                                  dir       => 'source');
$source->save;
push @categories, $source;
# Add a conflicting media in /to/that/source/
$conflict = $creator->create_media(category => $source,
                                   title    => "Conflict with From Media 2",
                                   filename => 'from_media_2',
                                   format   => 'jpg');
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 0);
};
diag('Testing Media conflict without overwrite - should throw exception');
isa_ok($@, 'Krang::Category::CopyAssetConflict');

#
# 5. Media conflict with overwrite
#
setup_tree();
# Add a TO category also existing in FROM
$source = pkg('Category')->new(parent_id => $that->category_id,
                                  dir       => 'source');
$source->save;
push @categories, $source;
# Add a conflicting media in /to/that/source/
$conflict = $creator->create_media(category => $source,
                                   title    => "Conflict with From Media 2",
                                   filename => 'from_media_2',
                                   format   => 'jpg');
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 1);
};
is(not($@), 1, 'Media conflict with overwrite');

#
# 6. Template conflict without overwrite
#
setup_tree();
# Add a TO category also existing in FROM
$source = pkg('Category')->new(parent_id => $that->category_id,
                               dir       => 'source');
$source->save;
push @categories, $source;
$water = pkg('Category')->new(parent_id => $source->category_id,
                              dir       => 'water');
$water->save;
push @categories, $water;

# Add a conflicting template in /to/that/source/water/
$conflict = $creator->create_template(category     => $water,
                                      element_name => 'from_template_2',
                                      content      => 'x');
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 0);
};
diag('Testing Template conflict without overwrite - should throw exception');
isa_ok($@, 'Krang::Category::CopyAssetConflict');

#
# 7. Template conflict with overwrite
#
setup_tree();
# Add a TO category also existing in FROM
$source = pkg('Category')->new(parent_id => $that->category_id,
                               dir       => 'source');
$source->save;
push @categories, $source;
$water = pkg('Category')->new(parent_id => $source->category_id,
                              dir       => 'water');
$water->save;
push @categories, $water;

# Add a conflicting template in /to/that/source/water/
$conflict = $creator->create_template(category     => $water,
                                      element_name => 'from_template_2',
                                      content      => 'x');
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 1);
};
is(not($@), 1, 'Template conflict with overwrite');

#
# 8. Resolvable URL Conflict between would-be-created category and story existing in TO
#
setup_tree();
$conflict = pkg('Story')->new(categories => [$that],
                              slug       => 'source',
                              class      => 'article',
                              title      => 'Conflicting with would-be-created source/ category');
$conflict->save;
push @stories, $conflict;
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 0);
};
is(not($@), 1, "Resolvable conflict between would-be-created category and slug-provided story in copy destination");

#
# 9. Unresolvable URL Conflict between would-be-created category and story existing in TO
#
setup_tree();
$conflict = pkg('Story')->new(categories => [$that],
                              slug       => 'source',
                              class      => 'article',
                              title      => 'Conflicting with would-be-created source/ category');
$conflict->save;
push @stories, $conflict;
$conflict->checkin();

# checkout as other user
diag("We are now another user - testing unresolvable conflict between would-be-created category and slug-provided story in copy destination");
{
    local $ENV{REMOTE_USER} = $user->user_id;

    $conflict->checkout;
    is($conflict->checked_out_by, $user->user_id, "Conflicting story checked out by other user");
}
diag("We are the normal test user again.");
eval {
    $this->can_copy_test(dst_category  => $that,
                         story     => 1,
                         media     => 1,
                         template  => 1,
                         overwrite => 0);
};
isa_ok($@, 'Krang::Story::CantCheckOut');
{
    diag("We are now another user");
    local $ENV{REMOTE_USER} = $user->user_id;

    $conflict->checkin;
    is($conflict->checked_out, 0, "Conflicting story is checked in back again.");
}
diag("We are the normal test user again.");

#   --- End tests ---

sub setup_tree {

    $_->delete for @stories;
    eval { $creator->cleanup() };
    $_->delete for reverse @categories;

    @categories = ();
    @stories    = ();

    $creator = pkg('Test::Content')->new;

############### Source Category Subtree ######################
    my $from = pkg('Category')->new(site_id => $site->site_id,
                                    dir     => 'from');
    $from->save;
    push @categories, $from;

    $this = pkg('Category')->new(parent_id => $from->category_id,
                                    dir       => 'this');
    $this->save;
    push @categories, $this;

    my $source = pkg('Category')->new(parent_id => $this->category_id,
                                      dir       => 'source');
    $source->save;
    push @categories, $source;

    my $water = pkg('Category')->new(parent_id => $source->category_id,
                                     dir       => 'water');
    $water->save;
    push @categories, $water;

    my $fresh = pkg('Category')->new(parent_id => $water->category_id,
                                     dir       => 'fresh');
    $fresh->save;
    push @categories, $fresh;

    # Some stories
    my $from_story_1 = pkg('Story')->new(categories => [$this],
                                         slug       => 'from_story_1',
                                         class      => 'article',
                                         title      => 'From Story 1');
    $from_story_1->save;
    push @stories, $from_story_1;

    my $from_story_2 = pkg('Story')->new(categories => [$source],
                                         slug       => 'from_story_2',
                                         class      => 'article',
                                         title      => 'From Story 2');
    $from_story_2->save;
    push @stories, $from_story_2;

    my $from_story_3 = pkg('Story')->new(categories => [$water],
                                         slug       => '',
                                         class      => 'article',
                                         title      => 'From Story 3 (slugless)');
    $from_story_3->save;
    push @stories, $from_story_3;

    # Some media
    my $from_media_1 = $creator->create_media(category => $this,
                                              title    => 'From Media 1',
                                              filename => 'from_media_1',
                                              format   => 'jpg',
                                             );

    my $from_media_2 = $creator->create_media(category => $source,
                                              title    => 'From Media 2',
                                              filename => 'from_media_2',
                                              format   => 'jpg',
                                             );

    # Some templates
    my $from_template_1 = $creator->create_template(category     => $this,
                                                    element_name => 'from_template_1',
                                                    content      => 'x');

    my $from_template_2 = $creator->create_template(category     => $water,
                                                    element_name => 'from_template_2',
                                                    content      => 'x');


############### Destination Category Subtree ######################
    my $to = pkg('Category')->new(site_id => $site->site_id,
                                  dir     => 'to');
    $to->save;
    push @categories, $to;

    $that = pkg('Category')->new(parent_id => $to->category_id,
                                    dir       => 'that');
    $that->save;
    push @categories, $that;

    my $destination = pkg('Category')->new(parent_id => $that->category_id,
                                           dir       => 'destination');
    $destination->save;
    push @categories, $destination;

    my $sea = pkg('Category')->new(parent_id => $destination->category_id,
                                   dir       => 'sea');
    $sea->save;
    push @categories, $sea;

    my $planet = pkg('Category')->new(parent_id => $sea->category_id,
                                      dir       => 'planet');
    $planet->save;
    push @categories, $planet;

    # Some stories
    my $to_story_1 = pkg('Story')->new(categories => [$that],
                                       slug       => 'to_story_1',
                                       class      => 'article',
                                       title      => 'To Story 1');
    $to_story_1->save;
    push @stories, $to_story_1;

    my $to_story_2 = pkg('Story')->new(categories => [$sea],
                                       slug       => '',
                                       class      => 'article',
                                       title      => 'To Story 2 (slugless)');
    $to_story_2->save;
    push @stories, $to_story_2;

    my $to_story_3 = pkg('Story')->new(categories => [$sea],
                                         slug       => 'to_story_3',
                                         class      => 'article',
                                         title      => 'To Story 3');
    $to_story_3->save;
    push @stories, $to_story_3;

    my $to_story_4 = pkg('Story')->new(categories => [$planet],
                                       slug       => 'to_story_4',
                                       class      => 'article',
                                       title      => 'To Story 4');
    $to_story_4->save;
    push @stories, $to_story_4;

    # Some media
    my $to_media_1 = $creator->create_media(category => $that,
                                            title    => 'To Media 1',
                                            filename => 'to_media_1',
                                            format   => 'jpg',
                                             );

    my $to_media_2 = $creator->create_media(category => $planet,
                                            title    => 'To Media 2',
                                            filename => 'to_media_2',
                                            format   => 'jpg',
                                           );

    # Some templates
    my $to_template_1 = $creator->create_template(category     => $sea,
                                                  element_name => 'to_template_1',
                                                  content      => 'x');

    my $to_template_2 = $creator->create_template(category     => $planet,
                                                  element_name => 'to_template_2',
                                                  content      => 'x');
}

END{
    $_->delete for @stories;
    $creator->cleanup();
    $_->delete for reverse @categories;
}