use Test::More tests => 8;
use strict;
use warnings;

BEGIN { use_ok('Krang::MethodMaker') }

package Foo;
use Krang::MethodMaker
  new     => 'new',
  get_set => [ qw(bar baz) ];

package main;

my $foo = Foo->new();
isa_ok($foo, 'Foo');
is($foo->bar, undef);
is($foo->bar('bar'), 'bar');
is($foo->bar, 'bar');
is($foo->bar(undef), undef);
is($foo->bar(), undef);
ok(!$foo->can('foo_clear'));
