#!/usr/bin/perl -w

=head1 NAME

MailServerLDAP

=head1 PREFACE

This package is a part of the YaST2 mail modul.

=head1 SYNOPSIS

use MailServerLDAP


=head1 DESCRIPTION

B<MailServerLDAP>  provides a function ConfigureLDAPServer that makes the local
LDAP server able to store the tables of the mail server.

=over 2

=cut

use strict;

package MailServerLDAP;

use YaST::YCP;

our %TYPEINFO;

YaST::YCP::Import ("Ldap");
YaST::YCP::Import ("YaPI::LdapServer");
YaST::YCP::Import ("Service");

BEGIN {$TYPEINFO{ConfigureLDAPServer} = ["function", "any"];}
sub ConfigureLDAPServer()
{
	# don't configure if using eDirectory server
	Ldap->CheckNDS ();
	if (! Ldap->nds())
	{
	    Ldap->Read();
	    my $ldapMap = Ldap->Export();
	    # Now we configure the LDAP-Server to be able store the mail server configuration
	    my $schemas = YaPI::LdapServer->ReadSchemaIncludeList();
	    my $SCHEMA  = join "",@{$schemas};
	    if( $SCHEMA !~ /dnszone.schema/ )
	    {
		push @{$schemas},'/etc/openldap/schema/dnszone.schema';
	    }
	    if( $SCHEMA !~ /suse-mailserver.schema/ )
	    {
		push @{$schemas},'/etc/openldap/schema/suse-mailserver.schema';
		YaPI::LdapServer->WriteSchemaIncludeList($schemas);
		my $indices = YaPI::LdapServer->ReadIndex($ldapMap->{ldap_domain});
		my $SuSEMailClient = 0;
		my $SuSEMailDomainMasquerading = 0;
		my $suseTLSPerSitePeer= 0;
		foreach my $index (@{$indices})
		{
		    if( $index->{attr} eq "SuSEMailClient,SUSEMailAcceptAddress,zoneName")
		    {
			$SuSEMailClient = 1;
		    }
		    if( $index->{attr} eq "SuSEMailDomainMasquerading,relativeDomainName,suseMailDomainType")
		    {
			$SuSEMailDomainMasquerading = 1;
		    }
		    if( $index->{attr} eq "suseTLSPerSitePeer,SuSEMailTransportDestination")
		    {
			$suseTLSPerSitePeer = 1;
		    }
		}
		if(!$SuSEMailClient)
		{
		    YaPI::LdapServer->AddIndex($ldapMap->{ldap_domain},
					       { "attr"  => "SuSEMailClient,SUSEMailAcceptAddress,zoneName",
						 "param" => "eq" }
					       );
		  }
		if(!$SuSEMailDomainMasquerading)
		{
		    YaPI::LdapServer->AddIndex($ldapMap->{ldap_domain},
					       { "attr"  => "SuSEMailDomainMasquerading,relativeDomainName,suseMailDomainType",
						 "param" => "eq" }
					       );
		  }
		if(!$suseTLSPerSitePeer)
		{
		    YaPI::LdapServer->AddIndex($ldapMap->{ldap_domain},
					       { "attr"  => "suseTLSPerSitePeer,SuSEMailTransportDestination",
						 "param" => "eq" }
					       );
		}
		YaPI::LdapServer->RecreateIndex($ldapMap->{ldap_domain});
	    }
	    Service->Restart("ldap");
	}
}
