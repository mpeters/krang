#!/usr/bin/env perl
use warnings;

##########################################
####  MODULES TO PRE-LOAD INTO KRANG  ####
##########################################

# setup load paths
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'AddOn';
# call the init-handler of any AddOns being used
BEGIN {
    print STDERR "Initializing AddOns...\n";
    pkg('AddOn')->call_handler('InitHandler');
}
use Krang::ClassLoader 'lib';
use Krang::ClassLoader Conf => qw(KrangRoot AvailableLanguages EnableTemplateCache);
use File::Find qw(find);
use File::Spec::Functions qw(catdir splitdir);
use Krang::ClassLoader 'HTMLTemplate';


# load all Krang libs, with a few exceptions
my $skip = qr/Profiler|Test|BricLoader|Cache|FTP|DataSet|Upgrade|MethodMaker|Daemon|Script|XML|ClassLoader/;
find({ 
      wanted => sub {
          return unless m!(Krang/.*).pm$!;
          my $path = $1;
          return if /^\.?#/; # skip emacs droppings
          return if /$skip/;

          my $pkg = join('::', (split(/\//, $path)));
          eval "use $pkg;";
          die "Problem loading $pkg:\n\n$@" if $@;
      },
      no_chdir => 1
     },
     KrangRoot . '/lib/Krang');

# load all templates for AvailableLanguages
my %languages = ();
@languages{ AvailableLanguages, 'en' } = ();

if( EnableTemplateCache ) {
print STDERR "Pre-loading HTML Templates...\n";

find(
     sub {
         return if /^\.?#/;                            # skip emacs droppings
         return if /\.base\.tmpl$/;                    # skip base templates
         my $lang = (splitdir($File::Find::dir))[-1];  #
         return unless exists $languages{$lang};       # skip unconfigured languages
         return unless /\.tmpl$/;                      # only templates

         pkg('HTMLTemplate')->new(
				   path     => $lang,
				   filename => $File::Find::name,
				   cache    => 1,
				   loop_context_vars => 1,
				  );
     },
     KrangRoot . '/templates');
}

# pre-load any addons that want it
print STDERR "Pre-loading AddOns...\n";
pkg('AddOn')->call_handler('PreloadHandler');

# these modules are lazy loaded so they don't get preloaded by default unless we do it explicitly
use Apache::Registry;
use Storable qw(freeze thaw);

print STDERR "Krang Pre-load complete.\n";

1;
