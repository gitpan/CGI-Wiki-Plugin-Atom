package CGI::Wiki::Plugin::Atom;

use strict;

use vars qw( $VERSION );
$VERSION = '0.01';

use POSIX 'strftime';
use Time::Piece;
use URI::Escape;
use Carp qw( croak );

sub new
{
  my $class = shift;
  my $self  = {};
  bless $self, $class;

  my %args = @_;
  my $wiki = $args{wiki};

  unless ($wiki && UNIVERSAL::isa($wiki, 'CGI::Wiki'))
  {
    croak 'No CGI::Wiki object supplied';
  }
  
  $self->{wiki} = $wiki;
  
  # Mandatory arguments.
  foreach my $arg (qw/site_name site_url make_node_url recent_changes_link atom_link/)
  {
    croak "No $arg supplied" unless $args{$arg};
    $self->{$arg} = $args{$arg};
  }
  
  # Optional arguments.
  foreach my $arg (qw/site_description software_name software_version software_homepage/)
  {
    $self->{$arg} = $args{$arg} || '';
  }

  $self->{timestamp_fmt} = $CGI::Wiki::Store::Database::timestamp_fmt;
  $self->{utc_offset} = strftime "%z", localtime;
  $self->{utc_offset} =~ s/(..)(..)$/$1:$2/;
  
  $self;
}

sub recent_changes
{
  my ($self, %args) = @_;

  my $wiki = $self->{wiki};

  my $generator = '';
  
  if ($self->{software_name})
  {
    $generator  = '  <generator';
    $generator .= ' uri="' . $self->{software_homepage} . '"'   if $self->{software_homepage};
    $generator .= ' version=' . $self->{software_version} . '"' if $self->{software_version};
    $generator .= ">\n";
    $generator .= $self->{software_name} . "</generator>\n";
  }                          

  my %criteria = (
                   ignore_case => 1,
                 );

  # If we're not passed any parameters to limit the items returned, default to 15.
  $args{days} ? $criteria{days}           = $args{days}
              : $criteria{last_n_changes} = $args{items} || 15;
  
  $criteria{metadata_wasnt} = { major_change => 0 }     if $args{ignore_minor_edits};
  $criteria{metadata_was}   = $args{filter_on_metadata} if $args{filter_on_metadata};

  my @changes = $wiki->list_recent_changes(%criteria);

  my $subtitle = $self->{site_description}
                 ? '<subtitle>' . $self->{site_description} . "</subtitle>\n"
                 : '';
                 
  my $atom = qq{<?xml version="1.0" encoding="UTF-8"?>

<feed xmlns="http://www.w3.org/2005/Atom">

  <link href="}            . $self->{site_url}            . qq{" />
  <title>}                 . $self->{site_name}           . qq{</title>
  <link rel="self" href="} . $self->{atom_link}           . qq{" />
  <updated>}               . $self->feed_timestamp(%args) . qq{</updated>
  <id>}                    . $self->{site_url}            . qq{</id>
  $subtitle};

  my (@urls, @items);

  foreach my $change (@changes)
  {
    my $node_name = $change->{name};

    my $item_timestamp = $change->{last_modified};
    
    # Make a Time::Piece object.
    my $time = Time::Piece->strptime($item_timestamp, $self->{timestamp_fmt});

    my $utc_offset = $self->{utc_offset};
    
    $item_timestamp = $time->strftime( "%Y-%m-%dT%H:%M:%S$utc_offset" );

    my $author      = $change->{metadata}{username}[0] || $change->{metadata}{host}[0] || 'Anonymous';
    my $description = $change->{metadata}{comment}[0]  || 'No description given for change';

    $description .= " [$author]" if $author;

    my $version = $change->{version};
    my $status  = (1 == $version) ? 'new' : 'updated';

    my $major_change = $change->{metadata}{major_change}[0];
       $major_change = 1 unless defined $major_change;
    my $importance = $major_change ? 'major' : 'minor';

    my $url = $self->{make_node_url}->($node_name, $version);

    # make XML-clean
    my $title =  $node_name;
       $title =~ s/&/&amp;/g;
       $title =~ s/</&lt;/g;
       $title =~ s/>/&gt;/g;
    
    push @items, qq{
  <entry>
    <title>$title</title>
    <link href="$url" />
    <id>$url</id>
    <summary>$description</summary>
    <updated>$item_timestamp</updated>
    <author><name>$author</name></author>
  </entry>
};

  }
  
  $atom .= join('', @items) . "\n</feed>\n";

  return $atom;   
}

sub feed_timestamp
{
  my ($self, %args) = @_;
  
  my %criteria = (ignore_case => 1);

  $args{days} ? $criteria{days}           = $args{days}
              : $criteria{last_n_changes} = $args{items} || 15;

  $criteria{metadata_wasnt} = { major_change => 0 }     if $args{ignore_minor_edits};
  $criteria{metadata_was}   = $args{filter_on_metadata} if $args{filter_on_metadata};

  my @changes = $self->{wiki}->list_recent_changes(%criteria);

  if ($changes[0]->{last_modified})
  {
    my $time = Time::Piece->strptime( $changes[0]->{last_modified}, $self->{timestamp_fmt} );

    my $utc_offset = $self->{utc_offset};
    
    return $time->strftime( "%Y-%m-%dT%H:%M:%S$utc_offset" );
  }
  else
  {
    return '1970-01-01T00:00:00+0000';
  }
}

1;

__END__

=head1 NAME

  CGI::Wiki::Plugin::Atom - A CGI::Wiki plugin to output RecentChanges RSS.

=head1 DESCRIPTION

This is an alternative access to the recent changes of a CGI::Wiki
wiki. It outputs the Atom Syndication Format as described at
L<http://www.atomenabled.org/developers/syndication/>.

This module is a straight port of L<CGI::Wiki::Plugin::RSS::ModWiki>.

=head1 SYNOPSIS

  use CGI::Wiki;
  use CGI::Wiki::Plugin::Atom;

  my $wiki = CGI::Wiki->new( ... );  # See perldoc CGI::Wiki

  # Set up the RSS feeder with the mandatory arguments - see
  # C<new()> below for more, optional, arguments.
  my $atom = CGI::Wiki::Plugin::Atom->new(
    wiki                => $wiki,
    site_name           => 'My Wiki',
    site_url            => 'http://example.com/',
    make_node_url       => sub
                           {
                             my ($node_name, $version) = @_;
                             return 'http://example.com/?id=' . uri_escape($node_name) . ';version=' . uri_escape($version);
                           },
    recent_changes_link => 'http://example.com/?RecentChanges',
    atom_link => 'http://example.com/?action=rc;format=atom',
  );

  print "Content-type: application/atom+xml\n\n";
  print $atom->recent_changes;

=head1 METHODS

=head2 C<new()>

  my $atom = CGI::Wiki::Plugin::Atom->new(
    # Mandatory arguments:
    wiki                 => $wiki,
    site_name            => 'My Wiki',
    site_url             => 'http://example.com/',
    make_node_url        => sub
                            {
                              my ($node_name, $version) = @_;
                              return 'http://example.com/?id=' . uri_escape($node_name) . ';version=' . uri_escape($version);
                            },
    recent_changes_link  => 'http://example.com/?RecentChanges',,
    atom_link => 'http://example.com/?action=rc;format=atom',

    # Optional arguments:
    site_description     => 'My wiki about my stuff',
    software_name        => $your_software_name,     # e.g. "CGI::Wiki"
    software_version     => $your_software_version,  # e.g. "0.73"
    software_homepage    => $your_software_homepage, # e.g. "http://search.cpan.org/dist/CGI-Wiki/"
  );

C<wiki> must be a L<CGI::Wiki> object. C<make_node_url>, if supplied, must 
be a coderef.

The mandatory arguments are:

=over 4

=item * wiki

=item * site_name

=item * site_url

=item * make_node_url

=item * recent_changes_link

=item * atom_link

=back

The three optional arguments

=over 4

=item * software_name

=item * software_version

=item * software_homepage

=back

are used to generate the C<generator> part of the feed.

=head2 C<recent_changes()>

  $wiki->write_node(
                     'About This Wiki',
                     'blah blah blah',
		                 $checksum,
              		   {
                       comment  => 'Stub page, please update!',
		                   username => 'Fred',
                     }
  );

  print "Content-type: application/atom+xml\n\n";
  print $atom->recent_changes;

  # Or get something other than the default of the latest 15 changes.
  print $atom->recent_changes( items => 50 );
  print $atom->recent_changes( days => 7 );

  # Or ignore minor edits.
  print $atom->recent_changes( ignore_minor_edits => 1 );

  # Personalise your feed further - consider only changes
  # made by Fred to pages about bookshops.
  print $atom->recent_changes(
             filter_on_metadata => {
                         username => 'Fred',
                         category => 'Bookshops',
                       },
              );

If using C<filter_on_metadata>, note that only changes satisfying
I<all> criteria will be returned.

B<Note:> Many of the fields emitted by the Atom generator are taken
from the node metadata. The form of this metadata is I<not> mandated
by L<CGI::Wiki>. Your wiki application should make sure to store some or
all of the following metadata when calling C<write_node>:

=over 4

=item B<comment> - a brief comment summarising the edit that has just been made; will be used in the summary for this item.  Defaults to the empty string.

=item B<username> - an identifier for the person who made the edit; will be used as the Dublin Core contributor for this item, and also in the RDF description.  Defaults to 'No description given for change'.

=item B<host> - the hostname or IP address of the computer used to make the edit; if no username is supplied then this will be used as the author for this item.  Defaults to 'Anonymous'.

=back

=head2 C<feed_timestamp()>

  print $atom->feed_timestamp();

Returns the timestamp of the feed in POSIX::strftime style ("Tue, 29 Feb 2000 
12:34:56 GMT"), which is equivalent to the timestamp of the most recent item 
in the feed. Takes the same arguments as recent_changes(). You will most likely
need this to print a Last-Modified HTTP header so user-agents can determine
whether they need to reload the feed or not.
  
=head1 SEE ALSO

=over 4

=item * L<CGI::Wiki>

=item * L<http://www.atomenabled.org/developers/syndication/>

=back

=head1 MAINTAINER

Earle Martin <EMARTIN@cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright 2006 Earle Martin.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 THANKS

Kake Pugh for originally writing CGI::Wiki::Plugin::RSS::ModWiki and indeed 
CGI::Wiki itself.

=cut