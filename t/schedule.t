use strict;
use warnings;

use Carp;
use File::Spec::Functions;
use File::Path;
use IO::File;
use Storable qw/freeze thaw/;

use Time::Piece;
use Time::Piece::MySQL;
use Time::Seconds;

use Krang::Script;
use Krang::Conf qw(KrangRoot InstanceElementSet);
use Krang::Session;
use Krang::DB qw(dbh);
use Krang::Test::Content;

use Data::Dumper;
use Config;


my $schedulectl;
my $restart;

# skip all tests unless a TestSet1-using instance is available
BEGIN {

    my $found;
    $schedulectl = File::Spec->catfile(KrangRoot, 'bin', 'krang_schedulectl');
    $restart = 0;

    foreach my $instance (Krang::Conf->instances) {
        Krang::Conf->instance($instance);
        if (InstanceElementSet eq 'TestSet1') {
            eval 'use Test::More qw(no_plan)';
            $found = 1;
            last;
        }
    }

    if ($found) {
        my $pidfile = File::Spec->catfile(KrangRoot, 'tmp', 'schedule_daemon.pid');
        if (-e $pidfile) {
            `$schedulectl stop`;
            sleep 5;
            if (-e $pidfile) {
                diag('Shutdown failed.  Exiting.');
                exit(1);
            } else {
                $restart = 1;
            }
        }
    } else {
        eval "use Test::More skip_all => 'test requires a TestSet1 instance';";
    }
    die $@ if $@;

}

END {
    if ($restart) {
        `$schedulectl start`;
    }
}


##################################################
##################################################
# SETUP
#

# Create needed Krang::Site, Krang::Category objects.

my $preview_url = 'scheduletest.preview.com';
my $publish_url = 'scheduletest.com';
my $preview_path = '/tmp/krangschedtest_preview';
my $publish_path = '/tmp/krangschedtest_publish';

my @schedules;

use_ok('Krang::Schedule');


# create story and media object.
my $creator = Krang::Test::Content->new();


my $site = $creator->create_site(
                                 preview_url  => $preview_url,
                                 publish_url  => $publish_url,
                                 preview_path => $preview_path,
                                 publish_path => $publish_path
                                );


my ($category) = Krang::Category->find(site_id => $site->site_id());

# Create needed Krang::Story and Krang::Media objects.
my $story = $creator->create_story(category => [$category]);
my $media = $creator->create_media(category => $category);


# Make sure live templates are undeployed, create and deploy
# a set of test templates for publishing.
$creator->undeploy_live_templates();
$creator->deploy_test_templates();



END {
    foreach (@schedules) {
        is($_->delete, 1, 'Krang::Schedule->delete()');
    }
    $creator->cleanup();
    rmtree $preview_path;
    rmtree $publish_path;
}

# make sure the default schedule objects are present
my ($tmp) = Krang::Schedule->find(object_type => 'tmp');
ok($tmp, 'tmp cleaner is present');
my ($session) = Krang::Schedule->find(object_type => 'session');
ok($session, 'session cleaner is present');
my ($analyze) = Krang::Schedule->find(object_type => 'analyze');
ok($analyze, 'db analyzer is present');
                                  


# 03/01 - is a saturday hence day_of_week - 6
my $date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');
my $publish_date = Time::Piece->from_mysql_datetime('2003-03-03 00:00:00');

my $sched = Krang::Schedule->new(
                                 action      => 'publish',
                                 object_id   => $story->story_id(),
                                 object_type => 'story',
                                 repeat      => 'never',
                                 date        => $publish_date,
                                 test_date   => $date,
                                );

isa_ok($sched, 'Krang::Schedule');

# save test
isa_ok($sched->save(), 'Krang::Schedule');

# capability test
can_ok($sched, ('new', 'context', 'object_id', 'priority', 'action', 'object_type',
                'repeat', 'day_of_week', 'hour', 'minute', 'next_run', 'last_run',
                'initial_date', 'schedule_id', 'find', 'execute', 'delete', 'determine_priority',
                'save', 'serialize_xml', 'deserialize_xml'));


# # check next run - should be $publish_date.
is($sched->next_run(), $publish_date->mysql_datetime, 'Krang::Schedule next_run()');

push @schedules, $sched;

# try and change repeat from 'never' - should die.
eval {
    $sched->repeat('daily');
};

$@ ? pass('Krang::Schedule->repeat()') : fail('Krang::Schedule->repeat()');



##################################################
##################################################
#
# Testing date-calculation
#

# Create new story publish job - repeats weekly - Mondays at noon.
$sched = Krang::Schedule->new(
                              action      => 'publish',
                              object_id   => $story->story_id(),
                              object_type => 'story',
                              repeat      => 'weekly',
                              day_of_week => 1,
                              hour        => 12,
                              minute      => 0,
                              test_date   => $date
                             );

isa_ok($sched, 'Krang::Schedule');

# save test
isa_ok($sched->save(), 'Krang::Schedule');

push @schedules, $sched;

# check next run - should be 2003-03-3 12:00:00.
$publish_date = Time::Piece->from_mysql_datetime('2003-03-03 12:00:00');

is($sched->next_run(), $publish_date->mysql_datetime, 'Krang::Schedule next_run()');

# change date to 2003-03-03 12:00:00 (publish time).
# Next publish should be 2003-03-10 12:00:00.
_check_calc_next_run($sched, '2003-03-03 12:00:00', '2003-03-03 12:00:00');

# change date to 2003-03-03 12:01:00 (1 minute past publish).
# Next publish should be 2003-03-10 12:00:00.
_check_calc_next_run($sched, '2003-03-03 12:01:00', '2003-03-10 12:00:00');

# change date to 2003-03-03 13:01:00 (1 hour, 1 minute past publish).
# Next publish should be 2003-03-10 12:00:00.
_check_calc_next_run($sched, '2003-03-03 13:01:00', '2003-03-10 12:00:00');

# change date to 2003-03-03 13:01:00 (1 minute before publish).
# Next publish should be 2003-03-03 12:00:00.
_check_calc_next_run($sched, '2003-03-03 11:59:00', '2003-03-03 12:00:00');

# change date to 2003-04-06 12:01:00 (one day before publish, some time in the future).
# Next publish should be 2003-04-07 12:00:00
_check_calc_next_run($sched, '2003-04-06 12:01:00', '2003-04-07 12:00:00');


# reset internal test date -- 2003-03-01 00:00:00
$date = Time::Piece->from_mysql_datetime('2003-03-01 12:00:00');
$publish_date = Time::Piece->from_mysql_datetime('2003-03-01 12:00:00');
$sched->_test_date($date);

# change repeat to daily - next_run should be $publish_date.
eval { $sched->repeat('daily'); };
$@ ? fail('Krang::Schedule->repeat()') : pass('Krang::Schedule->repeat()');

is($sched->next_run(), $publish_date->mysql_datetime, 'Krang::Schedule->next_run()');

# change date to 2003-03-01 12:00:00 (publish time)
# next publish should be 2003-03-02 12:00:00
_check_calc_next_run($sched, '2003-03-01 12:00:00', '2003-03-01 12:00:00');

# change date to 2003-03-01 12:01:00 (one minute after publish)-
# next publish should be 2003-03-02 12:00:00
_check_calc_next_run($sched, '2003-03-01 12:01:00', '2003-03-02 12:00:00');

# change date to 2003-03-01 13:00:00 (one hour after publish)-
# next publish should be 2003-03-02 12:00:00
_check_calc_next_run($sched, '2003-03-01 13:00:00', '2003-03-02 12:00:00');

# change date to 2003-03-01 11:59:00 - (one minute before publish)
# next publish should be 2003-03-01 12:00:00
_check_calc_next_run($sched, '2003-03-01 11:59:00', '2003-03-01 12:00:00');

# change date to 2003-03-01 10:59:00 - (one hour, one minute before publish)
# next publish should be 2003-03-01 12:00:00
_check_calc_next_run($sched, '2003-03-01 10:59:00', '2003-03-01 12:00:00');

# change date to 2003-03-01 23:59:00 - (one minute before midnight)
# next publish should be 2003-03-02 12:00:00
_check_calc_next_run($sched, '2003-03-01 23:59:00', '2003-03-02 12:00:00');


# reset internal test date -- 2003-03-01 00:00:00
$date = Time::Piece->from_mysql_datetime('2003-03-01 12:00:00');
$sched->_test_date($date);

# change repeat to hourly - next_run should be right now.
eval { $sched->repeat('hourly'); };
$@ ? fail('Krang::Schedule->repeat()') : pass('Krang::Schedule->repeat()');

is($sched->next_run(), $date->mysql_datetime, 'Krang::Schedule->next_run()');

# change date to 2003-03-01 00:01:00 (one minute past publish)
# next publish should be 2003-03-01 01:00:00
_check_calc_next_run($sched, '2003-03-01 00:01:00', '2003-03-01 01:00:00');

# change date to 2003-03-01 00:59:00 (one minute before next publish)
# next publish should be 2003-03-01 01:00:00
_check_calc_next_run($sched, '2003-03-01 00:59:00', '2003-03-01 01:00:00');


# change date to 2003-03-01 00:30:00 (30 minutes before next publish)
# next publish should be 2003-03-01 01:00:00
_check_calc_next_run($sched, '2003-03-01 00:30:00', '2003-03-01 01:00:00');


# change date to 2003-03-01 00:31:00 (31 minutes before next publish)
# next publish should be 2003-03-01 01:00:00
_check_calc_next_run($sched, '2003-03-01 00:31:00', '2003-03-01 01:00:00');


##################################################
##################################################
#
# Testing repeat changes
#

$date = Time::Piece->from_mysql_datetime('2003-03-01 12:00:00');

# Create new story publish job - repeats hourly.
$sched = Krang::Schedule->new(
                              action      => 'publish',
                              object_id   => $story->story_id(),
                              object_type => 'story',
                              repeat      => 'hourly',
                              minute      => 0,
                              test_date   => $date
                             );



is($sched->next_run(), $date->mysql_datetime, 'Krang::Schedule->next_run()');

isa_ok($sched, 'Krang::Schedule');

# save test
isa_ok($sched->save(), 'Krang::Schedule');

push @schedules, $sched;

# confirm hourly.
_check_calc_next_run($sched, '2003-03-01 00:00:00', '2003-03-01 00:00:00');
_check_calc_next_run($sched, '2003-03-01 00:01:00', '2003-03-01 01:00:00');
_check_calc_next_run($sched, '2003-03-01 00:59:00', '2003-03-01 01:00:00');


# change repeat to daily - it should croak.
eval { $sched->repeat('daily'); };
$@ ? pass('Krang::Schedule->repeat()') : fail('Krang::Schedule->repeat()');

# set hour - should pass now.
$sched->hour(0);
eval { $sched->repeat('daily'); };
$@ ? fail('Krang::Schedule->repeat()') : pass('Krang::Schedule->repeat()');

# confirm nextrun is still correct.
_check_calc_next_run($sched, '2003-03-01 00:00:00', '2003-03-01 00:00:00');
_check_calc_next_run($sched, '2003-03-01 00:01:00', '2003-03-02 00:00:00');
_check_calc_next_run($sched, '2003-03-01 23:59:00', '2003-03-02 00:00:00');


# change repeat to weekly - it should croak.
eval { $sched->repeat('weekly'); };
$@ ? pass('Krang::Schedule->repeat()') : fail('Krang::Schedule->repeat()');

# set hour - should pass now.
$sched->day_of_week(1);
eval { $sched->repeat('weekly'); };
$@ ? fail('Krang::Schedule->repeat()') : pass('Krang::Schedule->repeat()');

# confirm nextrun is still correct.
_check_calc_next_run($sched, '2003-03-01 00:00:00', '2003-03-03 00:00:00');
_check_calc_next_run($sched, '2003-03-03 00:01:00', '2003-03-10 00:00:00');
_check_calc_next_run($sched, '2003-03-09 23:59:00', '2003-03-10 00:00:00');


##################################################
##################################################
#
# Priority tests
#

$sched = Krang::Schedule->new(
                              action      => 'publish',
                              object_id   => $story->story_id(),
                              object_type => 'story',
                              repeat      => 'never',
                              date        => $publish_date,
                              test_date   => $date,
                             );
$sched->save();
push @schedules, $sched;

# priority should be 8 for a non-repeating story publish.
is($sched->priority(), 8, 'Krang::Schedule->priority()');

$sched->minute(0);
$sched->repeat('hourly');

# priority should be 5 for an hourly publish
is($sched->priority(), 5, 'Krang::Schedule->priority()');

$sched->hour(0);
$sched->repeat('daily');

# priority should be 6 for a daily publish
is($sched->priority(), 6, 'Krang::Schedule->priority()');

$sched->day_of_week(0);
$sched->repeat('weekly');

# priority should be 7 for a repeating story weekly publish.
is($sched->priority(), 7, 'Krang::Schedule->priority()');


# change to expiration.
$sched->action('expire');

# check to see that repeat was re-set to 'never'.
is($sched->repeat(), 'never', 'Krang::Schedule->action()');

# priority should be 4 for a one-time expire.
is($sched->priority(), 4, 'Krang::Schedule->priority()');


# change to alert.
$sched->action('send');

# check to see that repeat was re-set to 'never'.
is($sched->repeat(), 'never', 'Krang::Schedule->action()');

# priority should be 2 for an alert.
is($sched->priority(), 2, 'Krang::Schedule->priority()');


##################################################
##################################################
#
# Context Test
#
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');
$sched = Krang::Schedule->new(
                              action      => 'publish',
                              object_id   => $story->story_id(),
                              object_type => 'story',
                              repeat      => 'never',
                              date        => $date,
                              context     => ['version' => 1],
                              test_date   => $date,
                             );
$sched->save();
push @schedules, $sched;

# text 'context' behavior
is(ref $sched->{context}, 'ARRAY', 'Krang::Schedule->context()');
my %context1 = @{$sched->{context}};
is($context1{version}, 1, 'Krang::Schedule->context()');
is(exists $sched->{_frozen_context}, 1, 'Krang::Schedule->context()');
my %context2;
eval {%context2 = @{thaw($sched->{_frozen_context})}};
is($@, '', "Krang::Schedule->context() thaw");
is($context2{version}, $context1{version}, 'Krang::Schedule->context()');




##################################################
##################################################
#
# Action Tests
#

##############################
# publish

# bad test - create a schedule object with a bogus story_id.
# execute should fail.
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');

$sched = Krang::Schedule->new(
                              action      => 'publish',
                              object_id   => 16384,
                              object_type => 'story',
                              repeat      => 'hourly',
                              minute      => 0,
                              test_date   => $date
                             );
$sched->save();

# run the job - should fail.
eval { $sched->execute(); };

$@ ? pass('Krang::Schedule->execute(bogus story)') : fail('Krang::Schedule->execute(bogus story)');

# cleanup.
$sched->delete();


# create a schedule object to publish a story hourly.
$sched = Krang::Schedule->new(
                              action      => 'publish',
                              object_id   => $story->story_id(),
                              object_type => 'story',
                              repeat      => 'hourly',
                              minute      => 0,
                              test_date   => $date
                             );

$sched->save();
push @schedules, $sched;

# run the job.
eval { $sched->execute(); };

$@ ? fail('Krang::Schedule->execute()') : pass('Krang::Schedule->execute()');

# check to see if the stories exist
my @story_paths = $creator->publish_paths(story => $story);

foreach my $p (@story_paths) {
    ok(-e $p, 'Krang::Schedule->execute(publish)');
}

# check last_run and next_run - should be 2003-03-01 01:00:00.
is($sched->last_run(), $date->mysql_datetime, 'Krang::Schedule->last_run()');
$date += ONE_HOUR;
is($sched->next_run(), $date->mysql_datetime, 'Krang::Schedule->next_run()');

##############################
# expire

# ok - now another job to expire (delete) this one.

$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');

my $story_id = $story->story_id();
$sched = Krang::Schedule->new(
                              action      => 'expire',
                              object_id   => $story_id,
                              object_type => 'story',
                              repeat      => 'never',
                              date        => $date,
                              test_date   => $date
                             );
$sched->save();
my $sched_id = $sched->schedule_id();

push @schedules, $sched;

eval { $sched->execute(); };

$@ ? fail('Krang::Schedule->execute()' . $@) : pass('Krang::Schedule->execute()');

# check to see if the stories exist
foreach my $p (@story_paths) {
    ok(!-e $p, 'Krang::Schedule->execute(expire)');
}

my @storyfiles = Krang::Story->find(story_id => [$story_id]);
is($#storyfiles, -1, 'Krang::Schedule->execute(expire)');

# make sure that it removed itself.
my @schedule_files = Krang::Schedule->find(schedule_id => [$sched_id]);
is($#schedule_files, -1, 'deleting repeat(never) jobs');


##############################
# alert


# bad test - create a schedule object with a bogus story_id.
# execute should fail.
$date = Time::Piece->from_mysql_datetime('2003-03-01 00:00:00');

$sched = Krang::Schedule->new(
                              action      => 'send',
                              object_id   => 16384,
                              object_type => 'alert',
                              repeat      => 'hourly',
                              minute      => 0,
                              test_date   => $date
                             );
$sched->save();

# run the job - should fail.
eval { $sched->execute(); };

$@ ? pass('Krang::Schedule->execute(bogus alert)') : fail('Krang::Schedule->execute(bogus alert)');

# cleanup.
$sched->delete();


# NOTE:  Assumptions are being made that alerts function properly.


# Test tmp cleanup
my $tmpfile = File::Spec->catfile(KrangRoot, 'tmp', 'schedule_test');

# create a file in tmp with a date of 36 hours ago.
$date = localtime;
$date -= (ONE_HOUR * 36);

# need to use different touch syntax for linux vs BSD.
my $touch_string;

if ($Config{osname} =~ /bsd/i) {
    my $timestamp = sprintf("%04i%02i%02i%02i%02i.00", $date->year, $date->mon,
                            $date->mday, $date->hour, $date->minute);
    $touch_string = sprintf("touch -t %s %s", $timestamp, $tmpfile);
} else {
    $touch_string = sprintf("touch --date='%s' %s", $date->cdate, $tmpfile);
}

`$touch_string`;

if (-e $tmpfile) {

    $sched = Krang::Schedule->new(
                                  action      => 'clean',
                                  object_type => 'tmp',
                                  repeat      => 'daily',
                                  hour        => 3,
                                  minute      => 0,
                                 );

    $sched->save();

    push @schedules, $sched;

    eval { $sched->execute() };

    $@ ? fail("Krang::Schedule->_clean_tmp(): $@") : pass('Krang::Schedule->_clean_tmp()');

    (-e $tmpfile) ? fail('Krang::Schedule->_clean_tmp()') : pass('Krang::Schedule->_clean_tmp()');


} else {
    diag("Cannot touch $tmpfile.  Skipping tmp tests.");
}



# Test Session cleanup -- insert bad record.

my $dbh = dbh();
my $sess_id = 'abcdeftestsessiontesttest';
$date = localtime;

my $q = "INSERT INTO sessions (id, last_modified) values (?, ?)";

$dbh->do($q, undef, $sess_id, $date->mysql_datetime());

$sched = Krang::Schedule->new(
                              action      => 'clean',
                              object_type => 'session',
                              repeat      => 'daily',
                              hour        => 3,
                              minute      => 0
                             );
$sched->save();

push @schedules, $sched;

$sched->execute();

ok(Krang::Session->validate($sess_id), 'Krang::Schedule->_expire_sessions()');

# move date
$date -= (ONE_DAY * 2);

$q = "UPDATE sessions SET last_modified=? WHERE id=?";

$dbh->do($q, undef, $date->mysql_datetime(), $sess_id);

$sched->execute();

ok(!Krang::Session->validate($sess_id), 'Krang::Schedule->_expire_sessions()');


# cleanup

$q = "DELETE FROM sessions WHERE id=?";

$dbh->do($q, undef, $sess_id);



##################################################
##################################################
# Support subs
#


# given a Krang::Schedule object, and times for both 'now' and the publish date, figure
# out if Krang::Schedule->_calc_next_run() is returning the proper time.
sub _check_calc_next_run {
    my ($sched, $now_string, $publish_string) = @_;

    $date = Time::Piece->from_mysql_datetime($now_string);
    $publish_date = Time::Piece->from_mysql_datetime($publish_string);

    $sched->_test_date($date);

    my $ok = is($sched->_calc_next_run(), $publish_date->mysql_datetime, 'Krang::Schedule->_calc_next_run()');
    diag("failed date check: date='$now_string', pubdate='$publish_string'") unless ($ok);

}








