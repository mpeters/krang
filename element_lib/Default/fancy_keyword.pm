package Default::fancy_keyword;
use strict;
use warnings;

=head1 NAME

Default::fancy_keyword

=head1 DESCRIPTION

Default fancy keyword element class for Krang.  This element inherits
from Default::keyword and provides a fancier interface.  Instead of a
static list of four fields this element provides an [add more] button
to allow users to enter more data in the element.  Also, bulk edit
data is collected in a single element.

Since this element is meant to contain all the keywords for a single
story C<max> is set to 1.

=cut


use base 'Default::keyword';
use Carp qw(croak);
use Storable qw(freeze thaw);
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Log => qw(debug);

sub new {
   my $pkg = shift;
   my %args = ( name         => 'fancy_keyword', 
                display_name => 'Keywords',
                bulk_edit    => 1,
                max          => 1,
                @_
              );
   return $pkg->SUPER::new(%args);
}

sub input_form {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;

    # turn param into something unique that can be used as a
    # javascript identifier
    (my $jparam = $param) =~ s/\W//g;

    # get data (check the query first, and the element second)
    # and make sure it has at least required number of fields
    my @data;
    my %query_vars = $query->Vars();
    my $found      = 0;

    foreach my $key (keys %query_vars) {
        if( $key =~ /^\Q$param\E_(\d+)$/ ) {
            $found = 1;
            $data[$1] = $query_vars{$key} if( length $query_vars{$key} > 0 );
        }
    }

    # if we didn't find anything in the query
    unless( $found ) {
        @data = $element->data ? @{$element->data} : ();
    }

    # build text fields
    my $index = 0;
    my @fields =
      map { scalar $query->textfield(-name     => $param . '_' . $index++,
                                     -default  => $_,
                                     -size      => $self->size,
                                     ($self->maxlength ?
                                      (-maxlength => $self->maxlength) :
                                      ()))
        } @data;

    # pad them out
    my $field_html =
      join("\n",
           (map { '<div style="padding:2px">' . $_ . '</div>' } @fields));

    # get a dummy field like the real ones and spit it around the
    # field name
    my $dummy_field = '<div style="padding:2px">' .
      scalar $query->textfield(-name     => 'DUMMY',
                               -default  => "",
                               -size      => $self->size,
                               ($self->maxlength ?
                                (-maxlength => $self->maxlength) :
                                ())) .
                      '</div>';
    $dummy_field =~ s/"/\\"/g;
    my ($dummy_field_start, $dummy_field_end) =
      $dummy_field =~ /^(.*?)DUMMY(.*)$/;

    # javascript to add fields when "add more" is clicked
    my $html = <<END;
<script language="javascript">
  var ${jparam}_index = $index - 1;
  add_more_$jparam = function() {
      for(var i=0; i < 4; i++) {
        var index = ++${jparam}_index;
        var span = document.getElementById("${param}_add_" + index + "_span");
        span.innerHTML += "$dummy_field_start" +
                          "${param}_" + index  +
                          "$dummy_field_end" +
                           "\\n" +
                          "<div id=\\"${param}_add_" + (index + 1) + "_span\\"></div>";
      }
  }
</script>
$field_html
<div id="${param}_add_${index}_span"></div>
<input type="button" class="button" value="Add More" onclick="add_more_$jparam('$param')">
END

    # debug $html;
    return $html;
}

# unlike keywords, fancy keywords doesn't paginate by fields after
# bulk edit
sub bulk_edit_filter {
    my ($self, %arg) = @_;
    my ($data) = @arg{qw(data)};
    return [ @$data ];
}

sub fill_template {
    my ($self, %arg) = @_;

    my $tmpl = $arg{tmpl};

    return unless $arg{element}->data();

    # determine whether to populate as array or scalar
    if ($tmpl->query(name => [$self->name]) eq 'LOOP') {
        $tmpl->param($self->name => $arg{element}->data);
    } else {
        $tmpl->param($self->name => join(', ', @{$arg{element}->data}))
    }
}

# return a list of fields if no template exists.
sub template_data {
    my ($self, %args) = @_;

    if (my $data = $args{element}->data) {
        return join ', ', @$data;
    }
}


# return all keywords for indexing
sub index_data {
    my ($self, %arg) = @_;
    my ($element) = @arg{qw(element)};
    my $data = $element->data;
    return @$data if $data;
    return ();
}

# override the Default::keyword version since we could have
# double digit positions and string sort won't work
sub load_query_data {
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my $param = $element->xpath;
    my @data;
    foreach my $key ($query->param()) {
        if( $key =~ /^\Q$param\E_(\d+)$/ ) {
            $data[$1] = $query->param($key) if( length $query->param($key) > 0 );
            $query->delete($key);
        }
    }
    $element->data(\@data);
}



1;
