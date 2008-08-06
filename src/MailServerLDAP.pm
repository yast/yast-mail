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

YaST::YCP::Import ("YaPI::LdapServer");
YaST::YCP::Import ("Service");
YaST::YCP::Import ("Ldap");

BEGIN {$TYPEINFO{ConfigureLDAPServer} = ["function", [ "map" , "string", "any" ] ];}
sub ConfigureLDAPServer()
{
    my $ldapMap  = YaPI::LdapServer->ReadDatabaseList();
    # Now we configure the LDAP-Server to be able store the mail server configuration
    my $schemas = YaPI::LdapServer->ReadSchemaList();
    my $SCHEMA  = join "",@{$schemas};

    if( $SCHEMA !~ /dnszone/ )
    {
        YaPI::LdapServer->AddSchema('/etc/openldap/schema/dnszone.schema');
    }
    if( $SCHEMA !~ /suse-mailserver/ )
    {
        YaPI::LdapServer->AddSchema('/etc/openldap/schema/suse-mailserver.schema');
    }

    my $indices = YaPI::LdapServer->ReadIndex( $ldapMap->[2]->{'suffix'} );
    my @attrs = ( "SuSEMailClient", "SUSEMailAcceptAddress", "zoneName",
                  "SuSEMailDomainMasquerading", "relativeDomainName", "suseMailDomainType",
                  "suseTLSPerSitePeer", "SuSEMailTransportDestination" );
    foreach my $attr (@attrs){
        my $curindex;
        if (! defined $indices->{$attr} ) {
            $curindex->{'name'} = $attr;
            $curindex->{'eq'} = 1;
            YaPI::LdapServer->EditIndex($ldapMap->[2]->{'suffix'}, $curindex );
        }
    }
    return YaPI::LdapServer->ReadDatabase($ldapMap->[2]->{'suffix'});
}
