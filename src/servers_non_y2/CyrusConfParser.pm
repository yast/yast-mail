#!/usr/bin/perl
#
# $Id: CyrusConfParser.pm 23262 2005-05-03 11:30:49Z choeger $
#

=head1 NAME

CyrusConfParser

=head1 PREFACE

This package provides an objectoriented interface to read/write the cyrus-imapd
superserver configuration file cyrus.conf.

=head1 SYNOPSIS

  use CyrusConfParser;

  my $ccf = new CyrusConfParser("/etc/cyrus.conf");

  $ccf->readCyrusConf();
  $ccf->toggleService("imaps");
  $ccf->writeCyrusConf();


=head1 DESCRIPTION

Currently only toggling the comment sign of services within SERVICES section
of /etc/cyrus.conf implemented.

=head1 METHODS

=over 2

=cut

package CyrusConfParser;
use strict;
use Data::Dumper;
no warnings 'redefine';

######################################################################################
# external (public functions/methods)
######################################################################################

=item *
C<new();>

Instantiating a CyrusConfParser instance. Optional parameter can be a different
path to cyrus.conf and a reference to a logging function.

EXAMPLE:

  $_CFINST = new CyrusConfParser( "/etc/cyrus.conf", \&y2error );

=cut
sub new {
    my $this  = shift;
    my $file   = shift  || "/etc/cyrus.conf";
    my $logref = shift;

    if( defined $logref && $logref ne "" ) {
	*logger = $logref;
    }

    my $class = ref($this) || $this;
    my $self = {};
    $self->{cffile} = $file;

    bless $self, $class;
    return $self;
}

=item *
C<readCyrusConf();>

Read and parse cyrus.conf into internal format. This method must be invoked
before any other method can be invoked.

=cut

sub readCyrusConf {
    my $this = shift;

    my $fd;
    my $cf = $this->{cffile};
    
    if( ! open($fd, $cf) ) {
	logger("unable to open $cf\n");
	return 1;
    }
    
    my @CFA = <$fd>;
    chomp(@CFA);
    close($fd);
    
    my $cfa;
    for(my $c=0; $c<scalar(@CFA); $c++ ) {
        my $line;
        $line = $CFA[$c];
	push @$cfa, { 'ignore' => 1,
		      'line'   => $line };
	if( $line =~ /^SERVICES\s+\{/ ) {
	    $line = $CFA[++$c];
	    push @$cfa, { 'ignore' => 1,
			  'line'   => $line };
	    while( $line !~ /^\}/ ) {
		$line = $CFA[++$c];
		if( $line =~ /(\#?)\s+(imap|imaps|pop3|pop3s|sieve|lmtpunix)\s+cmd=\"?(.*?)\"?\s+listen=\"?(.*?)\"?\sprefork=(.*)/ ) {
		    my ($cmt, $sname, $sarg, $sport, $pfork ) = ($1, $2, $3, $4, $5);
		    #print "<$cmt><$sname><$sarg><$sport><$pfork>\n";
		    if( $cmt eq "#" ) {
			push @$cfa, { 'ignore'    => 0,
				      'commented' => 1,
				      'sname'     => $sname,
				      'sarg'      => $sarg,
				      'sport'     => $sport,
				      'pfork'     => $pfork };
		    } else {
			push @$cfa, { 'ignore'    => 0,
				      'commented' => 0,
				      'sname'     => $sname,
				      'sarg'      => $sarg,
				      'sport'     => $sport,
				      'pfork'     => $pfork };
		    }
		} else {
		    push @$cfa, { 'ignore' => 1,
				  'line'   => $line };
		}
	    }
	}
    }
    $this->{CCF} = $cfa;
    return 0;
}

=item *
C<writeCyrusConf();>

Write the internal data structure back to cyrus.conf

=cut

sub writeCyrusConf {
    my $this = shift;


    if( ! defined $this->{CCF} ) {
	logger("you have to call readCyrusConf() first\n");
	return 1;
    }

    my $fd;
    my $cf = $this->{cffile};

    if( ! open($fd, ">$cf") ) {
	logger("unable to open $cf\n");
	return 1;
    }

    foreach my $line ( @{$this->{CCF}} ) {
	if( $line->{ignore} ) {
	    print $fd "$line->{line}\n";
	} else {
	    $line->{pfork} = 0 if ! defined $line->{pfork};
	    if( $line->{commented} ) {
		print $fd "#  ".$line->{sname}."          cmd=\"".$line->{sarg}."\"".
		    " listen=\"".$line->{sport}."\" prefork=".$line->{pfork}."\n";
	    } else {
		print $fd "  ".$line->{sname}."          cmd=\"".$line->{sarg}."\"".
		    " listen=\"".$line->{sport}."\" prefork=".$line->{pfork}."\n";
	    }
	}
    }
    
    close($fd);
    return 0;
}

=item *
C<toggleService($service);>

Comment/Uncomment service $service

EXAMPLE:

    $ccf->togleService( "imaps" );

=cut

sub toggleService {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{CCF} ) {
	logger("you have to call readCyrusConf() first\n");
	return 1;
    }

    my $found = 0;
    foreach my $line ( @{$this->{CCF}} ) {
	next if $line->{ignore};
	if( $line->{sname} eq $srv ) {
	    $found = 1;
	    $line->{commented} = $line->{commented} ? 0 : 1;
	    last;
	}
    }
    return 1 if ! $found;
    return 0;
}

=item *
C<serviceEnabled($service);>

Check, whether $service is enabled (not commented)

EXAMPLE:

    $ccf->serviceEnabled( "imaps" );

=cut

sub serviceEnabled {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{CCF} ) {
	logger("you have to call readCyrusConf() first\n");
	return 1;
    }

    foreach my $line ( @{$this->{CCF}} ) {
	next if $line->{ignore};
	if( $line->{sname} eq $srv && ! $line->{commented} ) {
	    return 1;
	}
    }
    return 0;
}

=item *
C<serviceExists($service);>

Check, whether $service exists

EXAMPLE:

    $ccf->serviceExists( "imaps" );

=cut

sub serviceExists {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{CCF} ) {
	logger("you have to call readCyrusConf() first\n");
	return 1;
    }

    foreach my $line ( @{$this->{CCF}} ) {
	next if $line->{ignore};
	if( $line->{sname} eq $srv ) {
	    return 1;
	}
    }
    return 0;
}


=item *
C<addService($service);>

Add service $service

EXAMPLE:

    $ccf->addService( { sname => "imaps",
			sarg  => "imapd -s",
			sport => "imaps" } );

=cut

sub addService {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{CCF} ) {
	logger("you have to call readCyrusConf() first\n");
	return 1;
    }

    return 1 if ref($srv) ne "HASH";
    if( ( ! defined $srv->{sname} ) ||
	( ! defined $srv->{sport} ) ||
	( ! defined $srv->{sarg} ) ) {
	logger("you need to supply <sname>, <sport> and <sarg> in order to add a service\n");
	return 1;
    }
    $srv->{ignore} = 0;
    my $tmp;
    my $appended = 0;
    foreach my $s ( @{$this->{CCF}} ) {
	if( defined $s->{line} && $s->{line} =~ /^SERVICES/ ) {
	    push @$tmp, $s;
	    push @$tmp, $srv;
	} else {
	    push @$tmp, $s;
	}
    }

    $this->{CCF} = $tmp;

    return 0;
}

######################################################################################
# internal (private functions/methods)
######################################################################################

sub logger {
    my $line = shift || "";
    print STDERR "$line";
}

1;
