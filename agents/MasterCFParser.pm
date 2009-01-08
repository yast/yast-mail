#!/usr/bin/perl
#
# $Id: MasterCFParser.pm 30394 2006-04-24 10:12:22Z varkoly $
#

=head1 NAME

MasterCFParser

=head1 PREFACE

This package provides an objectoriented interface to read/write the postfix
superserver configuration file master.cf.

=head1 SYNOPSIS

  use MasterCFParser;

  my $msc = new MasterCFParser();
  $msc->readMasterCF();

  if( $msc->addService( { 'service' => 'smtps',
			  'type'    => 'inet',
			  'private' => 'n',
			  'unpriv'  => '-',
			  'chroot'  => 'n',
			  'wakeup'  => '-',
			  'maxproc' => '-',
			  'command' => 'smtpd',
		          'options' => { 'smtpd_tls_wrappermode' => 'yes',
				         'smtpd_sasl_auth_enable' => 'yes' }
		    }
		      ) ) {
    print "ERROR in addService()\n";
  }

  my $srvs = $msc->getServiceByAttributes( { 'command' => 'pipe',
				             'maxproc' => '10' } );
  if( ! defined $srvs ) {
    print "ERROR in getServiceByAttributes()\n";
  }

  if( $msc->modifyService( { 'service' => 'cyrus1',
			     'command' => 'pipe',
			     'type'    => 'unix' } ) ) {
    print "ERROR in modifyService()\n";
  }

=head1 DESCRIPTION

Each commented line of master.cf is internally presented as an hash containing
only one key/value pair, that is

  comment => "# a commented line"

Every other lines are represented as hash which MUST have the keys

  service,type,private,unpriv,chroot,wakeup,maxproc,command

and if present a key 'options'.

'options' can be either a scalar or a hash reference. A scalar for all so
called interfaces to non-Postfix software using the 'pipe' command. For all
other postfix commands, options must be a hash reference.

=head1 METHODS

=over 2

=cut

package MasterCFParser;
use strict;
no warnings 'redefine';

######################################################################################
# external (public functions/methods)
######################################################################################

=item *
C<new();>

Instantiating a MasterCFParser instance. Optional parameter can be a different
path to master.cf and a reference to a logging function.

EXAMPLE:

  $_CFINST = new MasterCFParser( $config->{"path"}, \&y2error );

=cut
sub new {
    my $this  = shift;
    my $path   = shift  || "/etc/postfix";
    my $logref = shift;

    if( defined $logref && $logref ne "" ) {
	*logger = $logref;
    }

    my $class = ref($this) || $this;
    my $self = {};
    $self->{cffile} = $path."/master.cf";

    bless $self, $class;
    return $self;
}

=item *
C<readMasterCF();>

Read and parse master.cf into internal format. This method must be invoked
before any other method can be invoked.

=cut

sub readMasterCF {
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
	if( $CFA[$c] =~ /^\s+/ ) {
	    logger("Syntax error in $cf, line ".($c+1)."\n");
	    return 1;
	}
	$line = $CFA[$c];
	while( defined $CFA[$c+1] && $CFA[$c+1] =~ /^\s+/ ) {
	    $line .= $CFA[++$c];
	}
	if( $line =~ /\w+/ )
	{ #avoid emty lines
		push @$cfa, line2service($line);
	}
    }
    $this->{MCF} = $cfa;
    return 0;
}

=item *
C<writeMasterCF();>

Write the internal data structure back to master.cf

=cut

sub writeMasterCF {
    my $this = shift;


    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return 1;
    }

    my $fd;
    my $cf = $this->{cffile};

    if( ! open($fd, ">$cf") ) {
	logger("unable to open $cf\n");
	return 1;
    }

    for(my $c=0; $c<scalar(@{$this->{MCF}}); $c++ ) {
	print $fd service2line($this->{MCF}->[$c])."\n";
    }

    close($fd);
    return 0;
}

=item *
C<deleteService($service);>

Delete service from internal data structure.
$service must contain keys 'service' and 'command', all other keys are ignored.

EXAMPLE:

    $msc->deleteService( { 'service' => 'smtps',
			   'command' => 'smtpd' } );

=cut

sub deleteService {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return 1;
    }

    return 1 if ref($srv) ne "HASH";
    if( (! defined $srv->{service}) ||
	(! defined $srv->{command}) ) {
	logger("to delete a service, keys 'service' and 'command' are required\n");
	return 1;
    }

    for(my $c=0; $c<scalar(@{$this->{MCF}}); $c++ ) {
	next if ! defined $this->{MCF}->[$c]->{service};
	if( $this->{MCF}->[$c]->{service} eq $srv->{service} &&
	    $this->{MCF}->[$c]->{command} eq $srv->{command} ) {
	    delete $this->{MCF}->[$c];
	}
    }
}

=item *
C<$hashref = getServiceByAttributes($service);>

Get all services matching specified attributes.

EXAMPLE:

  my $srvs = $msc->getServiceByAttributes( { 'command' => 'pipe',
				             'maxproc' => '10' } );

=cut

sub getServiceByAttributes {
    my $this  = shift;
    my $fsrv   = shift;

    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return undef;
    }

    return undef if ref($fsrv) ne "HASH";

    my $retsrv;
    my $nrkeys = scalar(keys(%$fsrv));
    my $foundmatches = 0;
    foreach my $s ( @{$this->{MCF}} ) {
	next if defined $s->{comment};
	$foundmatches = 0;
	foreach my $fs ( keys %$fsrv ) {
	    if( defined $fsrv->{$fs} && defined $s->{$fs} )
	    { 
		    $foundmatches++ if $fsrv->{$fs} eq $s->{$fs};
	    }
	}
	push @$retsrv, $s if $foundmatches == $nrkeys;
    }
    return $retsrv;
}

=item *
C<addService($service);>

Add a new service to internal data structure.
Every key MUST be given with the only exception of 'options', which is optional.

EXAMPLE:

    $msc->addService( { 'service' => 'smtps',
			'type'    => 'inet',
			'private' => 'n',
			'unpriv'  => '-',
			'chroot'  => 'n',
			'wakeup'  => '-',
			'maxproc' => '-',
			'command' => 'smtpd',
			'options' => { 'smtpd_tls_wrappermode' => 'yes',
				       'smtpd_sasl_auth_enable' => 'yes' }
		       }
		    );

=cut

sub addService {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return 1;
    }

    return 1 if not isValidService($srv);
    return 1 if $this->serviceExists($srv);

    if( $srv->{command} eq "pipe" ) {
	# if service has command pipe, then it is a an interface to
	# non-Postfix software, append at the end
	push @{$this->{MCF}}, $srv;
    } else {
	my $newcf;
	for(my $c=0; $c<scalar(@{$this->{MCF}}); $c++ ) {
	    if( defined $srv ) {
		my ($nc, $cmd) = $this->nextCommand($c);
		if( $cmd eq "pipe" ) {
		    push @$newcf, $srv;
		    while($c < $nc) {
			push @$newcf, $this->{MCF}->[$c++];
		    }
		    $srv = undef;
		}
	    }
	    push @$newcf, $this->{MCF}->[$c];
	}
	$this->{MCF} = $newcf;
    }
    return 0;
}

=item *
C<modifyService($service);>

Modify an existing service.
Keys 'service' and 'command' MUST be given.

modifyService replaces all keys of the matching internal service with the
given keys.

EXAMPLE:

    $msc->modifyService( { 'service' => 'cyrus1',
			   'command' => 'pipe',
			   'type'    => 'unix' } );

=cut

sub modifyService {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return 1;
    }

    return 1 if ref($srv) ne "HASH";
    return 1 if not ( defined $srv->{service} && defined $srv->{command} );
    return 1 if not $this->serviceExists($srv);

    foreach my $s ( @{$this->{MCF}} ) {
	next if ! defined $s->{service};
	if( $s->{service} eq $srv->{service} &&
	    $s->{command} eq $srv->{command} ) {
	    foreach my $k ( keys %$srv ) {
		$s->{$k} = $srv->{$k};
	    }
	}
    }

    return 0;
}

sub getRAWCF {
    my $this = shift;

    return $this->{MCF};
}


######################################################################################
# internal (private functions/methods)
######################################################################################

sub logger {
    my $line = shift || "";
    print STDERR "$line";
}

sub isValidService {
    my $srv = shift;

    return 0 if ref($srv) ne "HASH";
    return 0 if defined $srv->{comment};
    foreach my $k ( ( "service", "type", "private", "unpriv",
		      "chroot", "wakeup", "maxproc", "command" ) ) {
	if( (! defined $srv->{$k}) || $srv->{$k} eq "" ) {
	    logger("missing key <$k>\n");
	    return 0;
	}
    }
    return 1;
}

sub nextCommand {
    my $this = shift;
    my $pos  = shift;

    return ($pos, $this->{MCF}->[$pos]->{command}) if defined $this->{MCF}->[$pos]->{command};
    while( ! defined $this->{MCF}->[$pos]->{command} ) {
	$pos++;
    }
    
    return ($pos, $this->{MCF}->[$pos]->{command});
}

sub serviceExists {
    my $this  = shift;
    my $srv   = shift;

    foreach my $s ( @{$this->{MCF}} ) {
	next if ! defined $s->{service};
	if( $s->{service} eq $srv->{service} &&
	    $s->{command} eq $srv->{command} ) {
	    return 1;
	}
    }
    
    return 0;
}

sub service2line {
    my $srv = shift;

    my $line = '';
    if( defined $srv->{comment} ) {
	$line = $srv->{comment};
    } 
    elsif( defined $srv->{service} && $srv->{type} && $srv->{private} && $srv->{unpriv} && $srv->{chroot} && $srv->{wakeup} && $srv->{maxproc} && $srv->{command} )
    {
	$line = 
	    sprintf("%-8s %-5s %-6s %-7s %-7s %-8s %-7s %s",
		    $srv->{service},
		    $srv->{type},
		    $srv->{private},
		    $srv->{unpriv},
		    $srv->{chroot},
		    $srv->{wakeup},
		    $srv->{maxproc},
		    $srv->{command}
		    );
	if( defined $srv->{options} ) {
	    if( $srv->{command} eq "pipe" ) {
		$line .= "\n  ".$srv->{options};
	    } else {
		foreach my $key ( keys %{$srv->{options}} ) {
		    $line .= "\n  -o $key=$srv->{options}->{$key}";
		}
	    }
	}
    }
    return $line;
}

sub line2service {
    my $line = shift;

    if( $line =~ /^\#/ ) {
	return { 'comment' => $line };
    } else {
	# service type  private unpriv  chroot  wakeup  maxproc command + args
	my ($service,$type,$private,$unpriv,$chroot,$wakeup,$maxproc,$command) =
	    $line =~ /^(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*)/;
	
	my $options;
	# command has additional options?
	if( $command =~ /\s/ ) {
	    my $opts;
	    ($command,$opts) = $command =~ /^(.*?)\s+(.*)/;
	    if( defined $opts && $opts ne "" ) {
		if( $command ne "pipe" ) {
		    foreach my $opt ( split(/\s*-o\s*/,$opts) ) {
			next if $opt eq "";
			my ($key, $val) = $opt =~ /^(.*?)=(.*)/;
			$options->{$key} = $val;
		    }
		} else {
		    $options = $opts;
		}
	    }
	}
	
	return { 'service' => $service,
		 'type'    => $type,
		 'private' => $private,
		 'unpriv'  => $unpriv,
		 'chroot'  => $chroot,
		 'wakeup'  => $wakeup,
		 'maxproc' => $maxproc,
		 'command' => $command,
		 'options' => $options };
    }
}

1;
