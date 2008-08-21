
use inc::Module::Install;

name            ("IO-Plumbing");
abstract        ("pluggable, lazy access to system commands");
author          ("Sam Vilain <samv\@utsl.gen.nz>");
version_from    ("lib/IO/Plumbing.pm");
license         ("perl");

requires        ("perl" => 5.006001);  # backport patches welcome...
requires        ("Class::Autouse");
include         ("Test::Depends");
build_requires  ("Test::More");

no_index 'directory' => 'doc';  # (Module::Install)--

&WriteAll();

