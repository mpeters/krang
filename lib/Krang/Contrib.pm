package Krang::Contrib;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Conf qw(KrangRoot);
use Krang::Session qw(%session);
use Carp qw(croak);

# constants
use constant FIELDS => qw(contrib_id prefix first middle last suffix email phone bio url);

=head1 NAME

    Krang::Contrib - storage and retrieval of contributor data

=head1 SYNOPSIS

    # create new contributor object
    my $contrib = Krang::Contrib->new(  prefix => 'Mr.',
                                        first => 'Matthew',
                                        middle => 'Charles',
                                        last => 'Vella',
                                        email => 'mvella@thepirtgroup.com',
                                        phone => '111-222-3333',
                                        bio => 'This is my bio.',
                                        url => 'http://www.myurlhere.com' );

    # add contributor types (lets pretend contrib_type 1 is 'Writer' and 
    # type 3 is 'Photographer')
    $contrib->contrib_types(1,3);

    # save this contributor to the database
    $contrib->save();

    # now that it is saved we can get its id
    my $contrib_id = $contrib->contrib_id();

    # find this contributor by id
    my @contributors = Krang::Contrib->find( contrib_id => $contrib_id );

    # list contributor types (will return 1,3)
    $contributors[0]->contrib_types();

    # change contributor contrib types, effectively removing writer type (1)
    $contributors[0]->contrib_types(3);

    # save contributor, making changes permanent
    $contributors[0]->save();

    # delete contributor
    $contributors[0]->delete();

=head1 DESCRIPTION

This class handles the storage and retrieval of contributor data to/from the database. Contributor type ids come from Krang::ContribTyoes, but are associated to contributors here.

=head1 INTERFACE

=head2 METHODS

=over 

=item $contrib = Krang::Contrib->new()

new() suports the following name-value arguments:

=over

=item prefix

=item first

=item middle

=item last

=item suffix

=item email

=item phone

=item bio

=item url

All of the above are simply fields for storing arbitrary metadata

=back

=cut

use Krang::MethodMaker
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get_set       => [ qw( contrib_id prefix first middle last suffix email phone bio url )],
    list          => [ qw( contrib_types ) ];

sub init {
    my $self = shift;
    my %args = @_;

    $args{contrib_types} ||= [];

    # finish the object
    $self->hash_init(%args);

    return $self;
}

=item $contrib_id = $contrib->contrib_id()

Returns the unique id assigned the contributor object.  Will not be populated until $contrib->save() is called the first time.

=item $contrib->prefix()

=item $contrib->first()

=item $contrib->middle()

=item $contrib->last()

=item $contrib->suffix()

=item $contrib->email()

=item $contrib->phone()

=item $contrib->bio()

=item $contrib->url()

Gets/sets the value.

=item $contrib->contrib_types()

Returns an array of contrib_type_id's associated with this contributor.  Passing in array of ids sets them (overwriting any current type ids).

=cut

=item $contrib->save()

Save contributor oject to the database. Will set contrib_id if first save.

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;
    my $root = KrangRoot;
    my $session_id = $session{_session_id} || croak("No session id found");


    # if this is not a new contrib object
    if (defined $self->{contrib_id}) {
        my $contrib_id = $self->{contrib_id};

        # get rid of contrib_id from FIELDS, we don't have to reset it.
        my @fields = FIELDS;
        @fields = splice(@fields,1);

        $dbh->do('UPDATE contrib set '.join(',', (map { "$_ = ?" } @fields)).' WHERE contrib_id = ? ', undef, map { $self->{$_} } @fields, $contrib_id);
       
        # remove all contributor - contributor tyoe relations, we are going to re-add them 
        $dbh->do('DELETE from contrib_contrib_type where contrib_id = ?', undef, $contrib_id);
        foreach my $type_id (@{$self->{contrib_types}}) {
            $dbh->do('INSERT into contrib_contrib_type (contrib_id, contrib_type_id) VALUES (?,?)', undef, $contrib_id, $type_id);
        }
    } else {
        $dbh->do('INSERT INTO contrib ('.join(',', FIELDS).') VALUES (?,?,?,?,?,?,?,?,?,?)', undef, map { $self->{$_} } FIELDS);

        $self->{contrib_id} = $dbh->{mysql_insertid};
        my $contrib_id = $self->{contrib_id};

        foreach my $type_id (@{$self->{contrib_types}}) {
            $dbh->do('INSERT into contrib_contrib_type (contrib_id, contrib_type_id) VALUES (?,?)', undef, $contrib_id, $type_id);
        }
  
    }
} 

=item $contrib->delete() || Krang::Media->delete($contrib_id)

Permanently delete contrib object or contrib object with given id and contrib type associations.

=cut

sub delete {
    my $self = shift;
    my $contrib_id = shift;
    my $dbh = dbh;
    
    $contrib_id = $self->{contrib_id} if (not $contrib_id);

    croak("No contrib_id specified for delete!") if not $contrib_id;
    
    $dbh->do('DELETE from contrib where contrib_id = ?', undef, $contrib_id);
    $dbh->do('DELETE from contrib_contrib_type where contrib_id = ?', undef, $contrib_id);
}

=item @contrib = Krang::Contrib->find($param)

Find and return contributors with with parameters specified. Supported paramter keys:

=over 4

=item *

contrib_id

=item

first

=item

last

=item 

full_name - will search first, middle, last for matching LIKE strings

=item * 

order_by - field(s) to order search by, defaults to last,first. Can pass in list.

=item *

order_desc - results will be in ascending order unless this is set to 1 (making them descending).

=item *

limit - limits result to number passed in here, else no limit.

=item *

offset - offset results by this number, else no offset.

=item *

only_ids - return only contrib_ids, not objects if this is set true.

=item *

count - return only a count if this is set to true. Cannot be used with only_ids.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh;
    my @where;
    my @contrib_object;
    my $where_string;
    
    my $order_by =  $args{'order_by'} ? join(',',$args{'order_by'}) : 'last,first';
    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;

    foreach my $key (keys %args) {
        if ( ($key eq 'contrib_id') || ($key eq 'first') || ($key eq 'last') ) {
            push @where, $key;
        }
    }

    $where_string = join ' and ', (map { "$_ = ?" } @where);

    # add like search on first, last, middle for all full_name words
    if ($args{'full_name'}) {
        my @words = split(/\s+/, $args{'full_name'});
        foreach my $word (@words) {
            if ($where_string) {
               $where_string .= " and concat(first,' ',middle,' ',last) like ?"; 
            } else {
                $where_string = "concat(first,' ',middle,' ',last) like ?";
            }
            push (@where, $word);
            $args{$word} = "%$word%";
        }

    } 
    
    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*)';
    } elsif ($args{'only_ids'}) {
        $select_string = 'contrib_id';
    } else {
        $select_string = join(',', FIELDS);
    }

    my $sql = "select $select_string from contrib";
    $sql .= " where ".$where_string if $where_string;
    $sql .= " order by $order_by $order_desc";
    
    # add limit and/or offset if defined
    if ($limit) {
       $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, -1";
    }
    
    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");
    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{count};
        } elsif ($args{'only_ids'}) {
            $obj = $row->{contrib_id};
        } else {
            $obj = bless {}, $self;
            foreach my $field (FIELDS) {
                if ($row->{$field}) {
                    $obj->{$field} = $row->{$field};
                }
            }
        }
        push (@contrib_object,$obj);
    }
    $sth->finish();
    return wantarray ? @contrib_object: \@contrib_object;
}

=back

=cut

1;

