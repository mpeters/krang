package Krang::ElementClass::TopLevel;
use strict;
use warnings;

use Krang::Log qw(debug info critical);
use base 'Krang::ElementClass';

=head1 NAME

Krang::ElementClass::TopLevel - base class for top-level element classes

=head1 SYNOPSIS

  package ElementSet::article;
  use base 'Krang::ElementClass::TopLevel';

  # override new() to setup element class parameters
  sub new { 
      my $pkg = shift;
      my %arg = (name      => "article",
                 children  => [ 'deck', 'paragraph', 'image' ],
                 @_);
      return $pkg->SUPER::new(%arg); 
  }

  1;

=head1 DESCRIPTION

This class serves as the base class for top-level element classes.
The root of an element tree must start with a sub-class of this class.
The methods provided allow this special element to control some
aspects of the Story or Category which contains it.  For example, the
C<build_url> method allows element classes to determine how a story
builds its URL.

Additionally, some methods make no sense for a top-level element
class, and they are stubbed out with implementations that croak.  For
example, the C<input_form()> method is useless for a top-level element
because the UI does not allow top-level elements to recieve input.

=head1 INTERFACE

=over

=cut

# stub out interface methods that should never be called on a
# top-level object
BEGIN {
    no strict 'refs'; # needed for glob assign
    foreach my $meth (qw(input_form param_names bulk_edit_data 
                         bulk_edit_filter view_data validate 
                         load_query_data)) {
        *{"Krang::ElementClass::TopLevel::$meth"} = 
          sub { croak('$meth called on a top-level element!'); };
    }
}

=item C<< $url = $class->build_url(story => $story, category => $category) >>

Builds a URL for the given story and category.  The default
implementation takes the category url and appends a URI encoded copy
of the story slug.  This may be overriden by top level elements to
implement alternative URL schemes.  See L<Krang::ElementClass::Cover>
for an example.

=cut

sub build_url {
    my ($self, %arg) = @_;
    my ($story, $category) = @arg{qw(story category)};
    croak("Category not defined!") unless $category;
    return $category->url . CGI::Util::escape($story->slug || '');
}

=item C<< @fields = $class->url_attributes() >>

Returns a list of Story attributes that are being used to compute the
url in build_url().  For example, the default implementation returns
('slug') because slug is the only story attribute used in the URL.
L<Krang::ElementClass::Cover> returns an empty list because it uses no
story attributes in its C<build_url()>.

=cut

sub url_attributes { ('slug') }

=item C<< @schedules = $class->default_schedules(element => $element, story_id ==> $story_id) >>

Called when a top-level object is created.  May return a list of
Krang::Schedule objects.  The default implementation returns and empty
list.

=cut

sub default_schedules { return (); }

=item C<< $file_name = $class->filename() >>

Returns the filename (independant of the extension) to be used when writing to disk data generated by this element tree.  Will return C<index> unless overridden.

=cut

sub filename {
    return 'index';
}

=item C<< $file_extension = $class->extension() >>

Returns the file extension (see filename()) to be used when writing to disk data generated by this element tree.  Will return C<.html> unless overridden.

=cut

sub extension {
    return '.html';
}

=item C<< $class->save_hook(element => $element) >>

Called just before the story/category containing the element tree is
deleted.  The default implementation does nothing.

=cut

sub save_hook {}

=item C<< $class->delete_hook(element => $element) >>

Called just before the story/category containing the element tree is
deleted.  This routine can be used to do any necessary cleanup.  The
default implementation does nothing.

=cut

sub delete_hook {}

=item C<< $bool = $class->publish_check(element => $element) >>

This method is called before publishing the story via a scheduled
publish job (not in the UI).  If this method returns 0 the publish
won't happen.  This may be used to implement a "Holding" desk where
stories won't be automatically published, for example.

The default implementation just returns 1 in all cases.

=cut

sub publish_check { 1 }


=item C<< $bool = $class->force_republish(element => $element) >>

This method is called at the beginning of the publish process.  If
true, all other checks are ignored and the story is published.  If
false, other versioning and sanity checks (see L<Krang::Publisher> and
L<Krang::Story>) are made to determine whether or not to publish the
story.

The default implementation returns 0 in all cases.

=cut

sub force_republish { 0 }


=item C<< $bool = $class->use_category_templates(element => $element) >>

This method is called during the publish/preview process.  If true, it
will wrap the story output with the output of the category templates
before writing the result to the filesystem.  If false, the story
output is the final output.

The default implementation returns 1 (true) in all cases.

=cut

sub use_category_templates { 1 }


=item C<< $bool = $class->publish_category_per_page(element => $element) >>

This method is called during the publish/preview process.  If true, it
will re-publish the category element for each page in the story,
passing the current page number and total number of pages to the
category element.  The published output will be matched only with the
current page.

If false, the category element will be published once, and its output
will be matched up with each story page.

The default implementation returns 0 (false) in all cases.

Override this method to return 1 (true) if you want to generate
content on category templates varies for each page in a story.

=cut

sub publish_category_per_page { 0 }

=back

=cut

1;
