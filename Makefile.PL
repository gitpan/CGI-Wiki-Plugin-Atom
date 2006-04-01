use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => "CGI::Wiki::Plugin::Atom",
  VERSION_FROM => "lib/CGI/Wiki/Plugin/Atom.pm",
  PREREQ_PM    =>
                  {
                    CGI::Wiki   => 0.59,   # for metadata filtering
                    POSIX       => 0,      # strftime
                    Test::More  => 0,
                    Time::Piece => '1.08', # so strptime doesn't warn
                    URI::Escape => 0       # for testing
                  }
);
