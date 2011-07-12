#!/usr/bin/perl

BEGIN { push @INC, "/usr/lib/YaST2/servers_non_y2"; }

use strict;
use MasterCFParser;
my $DOMAIN=`postconf -h mydomain`;
chomp $DOMAIN;

if( ! "$DOMAIN" ) {
	print "Bad postfix configuration. mydomain can not be detected";
	exit 1;
}

#Generate the key
if( ! -e "/var/db/dkim/$DOMAIN.pem" ){
	print "Creating /var/db/dkim/$DOMAIN.pem\n";
	system( "mkdir -p /var/db/dkim/; amavisd genrsa /var/db/dkim/$DOMAIN.pem;");
}

#Introduce key into /etc/amavisd.conf
my $amavisd = "";
my $enable_dkim_signing = 0;
open IN, "</etc/amavisd.conf";
while(<IN>)
{
	if( /^\$inet_socket_port/ )
	{
		$amavisd .= '$inet_socket_port = [10024,10026];'."\n";
		next;
	}
	if( /^\$enable_dkim_signing/ )
	{
		$amavisd .= '$enable_dkim_signing = 1;'."\n";
		$enable_dkim_signing = 1;
		next;
	}
	if( $enable_dkim_signing )
	{
		my $dkim = "dkim_key('$DOMAIN', 'default', '/var/db/dkim/$DOMAIN.pem');";
		if( ! /$dkim/ )
		{
			$amavisd .= "$dkim\n$_";
		}	
		$enable_dkim_signing = 0;
		next;
	}
	$amavisd .= $_;
}
close IN;
system("cp /etc/amavisd.conf /etc/amavisd.conf.backup");
open  OUT, ">/etc/amavisd.conf";
print OUT $amavisd;
close OUT;

#Now we adapt master.cf
my $msc = new MasterCFParser();
$msc->readMasterCF();

if( ! $msc->serviceExists( { service => 'submission' , command => 'smtpd' } ))
{
	if( $msc->addService( { 'service' => 'submission',
	                        'type'    => 'inet',
	                        'private' => 'n',
	                        'unpriv'  => '-',
	                        'chroot'  => 'n',
	                        'wakeup'  => '-',
	                        'maxproc' => '-',
	                        'command' => 'smtpd',
	                        'options' => { 'content_filte' => 'amavis:[127.0.0.1]:10026',
	                                       'smtpd_recipient_restrictions' => 'permit_sasl_authenticated,permit_mynetworks,reject' }
	                  }) )
	{
		print "ERROR in addService()\n";
	}
}
else
{
	if( $msc->modifyService( { 'service' => 'submission',
	                        'type'    => 'inet',
	                        'private' => 'n',
	                        'unpriv'  => '-',
	                        'chroot'  => 'n',
	                        'wakeup'  => '-',
	                        'maxproc' => '-',
	                        'command' => 'smtpd',
	                        'options' => { 'content_filte' => 'amavis:[127.0.0.1]:10026',
	                                       'smtpd_recipient_restrictions' => 'permit_sasl_authenticated,permit_mynetworks,reject' }
	                  }) )
	{
		print "ERROR in modifyService()\n";
	}
}

$msc->writeMasterCF();
