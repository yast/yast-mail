=head1 NAME

YaPI::MailServer

=head1 PREFACE

This package is the public Yast2 API to configure the postfix.
Representation of the configuration of mail-server.
Input and output routines.

=head1 SYNOPSIS

use YaPI::MailServer


=head1 DESCRIPTION

B<YaPI::MailServer>  is a collection of functions that implement a mail server
configuration API to for Perl programs.

=over 2

=cut




package YaPI::MailServer;

use strict;
use vars qw(@ISA);

use ycp;
use YaST::YCP;
use YaPI;
@YaPI::MailServer::ISA = qw( YaPI );

use POSIX;     # Needed for setlocale()
use Data::Dumper;
use Net::IMAP;

textdomain("mail");
our %TYPEINFO;
our @CAPABILITIES = (
                     'SLES10'
                    );
our $VERSION="2.2.0";

YaST::YCP::Import ("SCR");
YaST::YCP::Import ("Service");
YaST::YCP::Import ("Ldap");
YaST::YCP::Import ("NetworkInterfaces");

##
 #
my $proposal_valid = 0;

##
 # Some global variables
my $imapadm  = "cyrus";
my $imaphost = "localhost";
my $aconf    = "/etc/amavisd.conf";

##
 # Write only, used during autoinstallation.
 # Don't run services and SuSEconfig, it's all done at one place.
 #
my $write_only = 0;

BEGIN { $TYPEINFO{ReadMasterCF}  =["function", "any"  ]; }
sub ReadMasterCF {
    my $MasterCf  = SCR->Read('.mail.postfix.mastercf');

    return $MasterCf;
}

BEGIN { $TYPEINFO{findService}  =["function", "any"  ]; }
sub findService {
    my ($service, $command ) = @_;

    my $services  = SCR->Read('.mail.postfix.mastercf.findService', $service, $command);

    return $services;
}
=item *
C<$GlobalSettings = ReadGlobalSettings($$AdminPassword)>

 Dump the mail-server Global Settings to a single hash
 Return hash Dumped settings (later acceptable by WriteGlobalSettings ())

 $GlobalSettings is a pointer to a hash containing the basic settings of 
 the mail server.

 %GlobalSettings = (
       'Changed'               => 0,
            Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

       'MaximumMailSize'       => 0,
            Shows the maximum message size in bytes, the mail server will accept 
            to deliver. Setting this value 0 means there is no limit.

       'Banner'                => '$myhostname ESMTP $mail_name'
            The smtpd_banner parameter specifies the text that follows the 220
            code in the SMTP server's greeting banner. Some people like to see
            the mail version advertised. By default, Postfix shows no version.
            You MUST specify $myhostname at the start of the text. That is an
            RFC requirement. Postfix itself does not care.

       'Interfaces'            => ''
            The inet_interfaces parameter specifies the network interface
            addresses that this mail system receives mail on.  By default,
            the software claims all active interfaces on the machine. The
            parameter also controls delivery of mail to user@[ip.address]
       
       'SendingMail'           => {
            In this hash you can define the type of delivery of outgoing emails.
	    
            'Type'          => '',
                Shows the type of the delivery of the outgoing mails. Possible 
                values are: 
	        DNS : Delivery via DNS lookup of the MX records of the
		      destination domain.
		relayhost : Delivery using a relay host
		NONE : There is no delivery of outgoing mails. In this case
		       some other funcions are not avaiable. For example
		       setting of mail transport.
		       
            'TLS'           => '',
	        If delivery via DNS is used you can set how TLS will be used
		for security. Possible values are:
		NONE    : don't use TLS.
		MAY     : TLS will used when offered by the server.
		MUST    : Only connection with TLS will be accepted.
		MUST_NOPEERMATCH  : Only connection with TLS will be accepted, but
		          no strict peername checking accours.
			  
            'RelayHost'     => {
	        If the type of delivery of outgoing emails is set to "relayhost",
		then you have to define the relyhost in this hash.
		
                  'Name'     => '',
		        DNS name or IP address of the relay host.
			
                  'Auth'     => 0,
		        Sets if SASL authentication will be used for the relayhost.
			Possible values are: 0 (no) and 1 (yes).
			
                  'Account'  => '',
		        The account name of the SASL account.
			
                  'Password' => ''
		        The SASL account password
                }
          }
     );

EXAMPLE:

use MailServer;

    my $AdminPassword   = "VerySecure";


=cut

BEGIN { $TYPEINFO{ReadGlobalSettings}  =["function", ["map", "string", "any" ], "string"]; }
sub ReadGlobalSettings {
    my $self            = shift;
    my $AdminPassword   = shift;

    my %GlobalSettings = ( 
                'Changed'               => YaST::YCP::Boolean(0),
                'MaximumMailSize'       => 0,
                'Banner'                => '$myhostname ESMTP $mail_name',
                'SendingMail'           => { 
                         'Type'          => 'DNS',
                         'TLS'           => 'NONE',
                         'RelayHost'     => {
                                'Name'     => '',
                                'Auth'     => 0,
                                'Account'  => '',
                                'Password' => ''
                              }
                         
                       }
          );

    my $MainCf    = SCR->Read('.mail.postfix.main.table');
    my $SaslPaswd = SCR->Read('.mail.postfix.saslpasswd.table');
    if( ! SCR->Read('.mail.postfix.mastercf') )
    {
         return $self->SetError( summary =>"Couln't open master.cf",
                                 code    => "PARAM_CHECK_FAILED" );
    }

    # Reading maximal size of transported messages
    $GlobalSettings{'MaximumMailSize'}  = read_attribute($MainCf,'message_size_limit');

    #
    $GlobalSettings{'Banner'}           = `postconf -h smtpd_banner`;
    $GlobalSettings{'Interfaces'}       = `postconf -h inet_interfaces`;
    chomp $GlobalSettings{'Banner'};

    # Determine if relay host is used
    $GlobalSettings{'SendingMail'}{'RelayHost'}{'Name'} = read_attribute($MainCf,'relayhost');

    if($GlobalSettings{'SendingMail'}{'RelayHost'}{'Name'} ne '')
    {
      # If relay host is used read & set some parameters
            $GlobalSettings{'SendingMail'}{'Type'} = 'relayhost';
        
        # Determine if relay host need sasl authentication
        my $tmp = read_attribute($SaslPaswd,$GlobalSettings{'SendingMail'}{'RelayHost'}{'Name'}); 
        if( $tmp )
	{
            ($GlobalSettings{'SendingMail'}{'RelayHost'}{'Account'},$GlobalSettings{'SendingMail'}{'RelayHost'}{'Password'}) 
	                 = split /:/,$tmp;
        }
        if($GlobalSettings{'SendingMail'}{'RelayHost'}{'Account'}  ne '')
	{
           $GlobalSettings{'SendingMail'}{'RelayHost'}{'Auth'} = 1;
        }
    }
    else
    {
	my $smtpsrv = SCR->Execute('.mail.postfix.mastercf.findService',
		{ 'service' => 'smtp',
		  'command' => 'smtp' });
        if( defined $smtpsrv )
	{
            $GlobalSettings{'SendingMail'}{'Type'} = 'DNS';
	}
	else
	{   
            $GlobalSettings{'SendingMail'}{'Type'} = 'NONE';
	}    
    }
    if( $GlobalSettings{'SendingMail'}{'Type'} ne 'NONE')
    {
	    my $USE_TLS          = read_attribute($MainCf,'smtp_use_tls');
	    my $ENFORCE_TLS      = read_attribute($MainCf,'smtp_enforce_tls');
	    my $ENFORCE_PEERNAME = read_attribute($MainCf,'smtp_tls_enforce_peername');
	    if($USE_TLS eq 'no' && $ENFORCE_TLS ne 'yes')
	    {
               $GlobalSettings{'SendingMail'}{'TLS'} = 'NONE';
	    }
	    elsif( $ENFORCE_TLS eq 'yes')
	    {
	      if( $ENFORCE_PEERNAME eq 'no')
	      {
                 $GlobalSettings{'SendingMail'}{'TLS'} = 'MUST_NOPEERMATCH';
	      }
	      else
	      {
                 $GlobalSettings{'SendingMail'}{'TLS'} = 'MUST';
	      } 
	    }
	    else
	    {
                 $GlobalSettings{'SendingMail'}{'TLS'} = 'MAY';
	    }
    }	    
    
    return \%GlobalSettings;
}

=item *
C<boolean = WriteGlobalSettings($GlobalSettings)>

Write the mail-server Global Settings from a single hash
@param settings The YCP structure to be imported.
@return boolean True on success

EXAMPLE:

This example shows the setting up of the mail server bsic configuration
using a relay host with SASL authetication and TLS security.
Furthermore there will be set the maximum mail size, which the mail server
will be accept to deliver, to 10MB.

use MailServer;

    my $AdminPassword   = "VerySecure";

    my %GlobalSettings = (
                   'Changed'               => 1,
                   'MaximumMailSize'       => 10485760,
                   'Banner'                => '$myhostname ESMTP $mail_name',
                   'SendingMail'           => {
                           'Type'          => 'relayhost',
                           'TLS'           => 'MUST',
                           'RelayHost'     => {
                                   'Name'     => 'mail.domain.de',
                                   'Auth'     => 1,
                                   'Account'  => 'user',
                                   'Password' => 'password'
                                 }
                         }
             );

   if( ! WriteGlobalSettings(\%GlobalSettings,$AdminPassword) ) {
        print "ERROR in WriteGlobalSettings\n";
   }

=cut

BEGIN { $TYPEINFO{WriteGlobalSettings}  =["function", "boolean",  ["map", "string", "any" ], "string"]; }
sub WriteGlobalSettings {
    my $self               = shift;
    my $GlobalSettings     = shift;
    my $AdminPassword      = shift;

    if(! $GlobalSettings->{'Changed'})
    {
         return $self->SetError( summary =>"Nothing to do",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    y2milestone("-- WriteGlobalSettings --");

    my $MaximumMailSize    = $GlobalSettings->{'MaximumMailSize'};
    my $Interfaces         = $GlobalSettings->{'Interfaces'}  || 'all';
    my $SendingMailType    = $GlobalSettings->{'SendingMail'}{'Type'};
    my $SendingMailTLS     = $GlobalSettings->{'SendingMail'}{'TLS'};
    my $RelayHostName      = $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Name'};
    my $RelayHostAuth      = $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Auth'};
    my $RelayHostAccount   = $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Account'};
    my $RelayHostPassword  = $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Password'};
    my $MainCf             = SCR->Read('.mail.postfix.main.table');
    my $SaslPasswd         = SCR->Read('.mail.postfix.saslpasswd.table');
    if( ! SCR->Read('.mail.postfix.mastercf') )
    {
         return $self->SetError( summary =>"Couln't open master.cf",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Parsing attributes 
    if($MaximumMailSize =~ /[^\d+]/)
    {
         return $self->SetError( summary =>"Maximum Mail Size value may only contain decimal number in byte",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    # If SendingMailType ne NONE we have to have a look 
    # at master.cf if smt is started
    if($SendingMailType ne 'NONE')
    {
       my $smtpsrv = SCR->Execute('.mail.postfix.mastercf.findService',
                   { 'service' => 'smtp',
                     'command' => 'smtp' });
       if(! defined $smtpsrv )
       {
           SCR->Execute('.mail.postfix.mastercf.addService', { 'service' => 'smtp',
                        'type'    => 'inet',
                        'private' => 'n',
                        'unpriv'  => '-',
                        'chroot'  => 'n',
                        'wakeup'  => '-',
                        'maxproc' => '-',
                        'command' => 'smtpd' });
       }
    }
    
    if($SendingMailType eq 'DNS')
    {
        #Make direkt mail sending
        #looking for relayhost setting from the past 
        my $tmp = read_attribute($MainCf,'relayhost');
        if( $tmp ne '' )
	{
            write_attribute($MainCf,'relayhost','');
            write_attribute($SaslPasswd,$tmp,'');
        }
    }
    elsif ($SendingMailType eq 'relayhost')
    {
        write_attribute($MainCf,'relayhost',$RelayHostName);
        if($RelayHostAuth)
	{
           write_attribute($SaslPasswd,$RelayHostName,"$RelayHostAccount:$RelayHostPassword");
           write_attribute($MainCf,'smtp_sasl_auth_enable','yes');
           write_attribute($MainCf,'smtp_sasl_password_maps','hash:/etc/postfix/sasl_passwd');
        }
    }
    elsif ($SendingMailType eq 'NONE')
    {
	SCR->Execute('.mail.postfix.mastercf.deleteService', { 'service' => 'smtp', 'command' => 'smtp' });
    }
    else
    {
      return $self->SetError( summary =>"Unknown mail sending type. Allowed values are:".
                                          " NONE | DNS | relayhost",
                              code    => "PARAM_CHECK_FAILED" );
    }
    #Now we write TLS settings if needed
    if($SendingMailTLS eq 'NONE')
    {
      write_attribute($MainCf,'smtp_use_tls','no');
      write_attribute($MainCf,'smtp_enforce_tls','no');
      write_attribute($MainCf,'smtp_tls_enforce_peername','no');
    }
    elsif($SendingMailTLS eq 'MAY')
    {
      write_attribute($MainCf,'smtp_use_tls','yes');
      write_attribute($MainCf,'smtp_enforce_tls','no');
      write_attribute($MainCf,'smtp_tls_enforce_peername','yes');
    }
    elsif($SendingMailTLS eq 'MUST')
    {
      write_attribute($MainCf,'smtp_use_tls','yes');
      write_attribute($MainCf,'smtp_enforce_tls','yes');
      write_attribute($MainCf,'smtp_tls_enforce_peername','yes');
    }
    elsif($SendingMailTLS eq 'MUST_NOPEERMATCH')
    {
      write_attribute($MainCf,'smtp_use_tls','yes');
      write_attribute($MainCf,'smtp_enforce_tls','yes');
      write_attribute($MainCf,'smtp_tls_enforce_peername','no');
    }
    else
    {
      return $self->SetError( summary =>"Unknown mail sending TLS type. Allowed values are:".
                                          " NONE | MAY | MUST | MUST_NOPEERMATCH",
                              code    => "PARAM_CHECK_FAILED" );
    }

    write_attribute($MainCf,'inet_interfaces',$Interfaces);
    write_attribute($MainCf,'message_size_limit',$MaximumMailSize);
    write_attribute($MainCf,'smtpd_banner',$GlobalSettings->{'Banner'});
    write_attribute($MainCf,'smtp_sasl_security_options','noanonymous');

    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.mail.postfix.main',undef);
    SCR->Write('.mail.postfix.saslpasswd.table',$SaslPasswd);
    SCR->Write('.mail.postfix.saslpasswd',undef);
    SCR->Write('.mail.postfix.mastercf',undef);

    return 1;
}

=item *
C<$Canonical = ReadCanonical($AdminPassword)>

  Dump the mail-server Mail Transport to a single hash
  @return hash Dumped settings (later acceptable by WriteCanonical ())

=cut

BEGIN { $TYPEINFO{ReadCanonical}  =["function", ["map", "string", "any"]  , "string"]; }
sub ReadCanonical
{
    my $self            = shift;
    my $AdminPassword   = shift;


    my %Canonicals       = ( 
                           'Changed'          => YaST::YCP::Boolean(0),
                           'CanonicalTable'   => [], 
                           'CanonicalClasses' => [] 
                          );


    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }
    my $MainCf           = SCR->Read('.mail.postfix.main.table');
    my $CanonicalClasses = read_attribute($MainCf,'transport_maps');
    $CanonicalClasses    =~ s/ //g;
    push @{$Canonicals{CanonicalClasses}}, split /,/,$CanonicalClasses;

    my %SearchMap       = (
                               'base_dn'    => $ldapMap->{'mail_config_dn'},
                               'filter'     => "objectClass=suseCanonicalTable",
                               'scope'      => 2,
                               'map'        => 1,
                               'attributes' => ['tableKey',
			                        'tableValue',
						'valueType',
						'description' ]
                          );

                             
    # Searching all the transport lists
    my $ret = SCR->Read('.ldap.search',\%SearchMap);

    # filling up our array
    foreach my $dn (keys %{$ret})
    {
       my $Canonical       = {};
       $Canonical->{'key'}     = $ret->{$dn}->{'tableKey'}->[0];
       $Canonical->{'value'}   = $ret->{$dn}->{'tableValue'}->[0];
       $Canonical->{'type'}    = $ret->{$dn}->{'valueType'}->[0];
       if( defined $ret->{$dn}->{'description'}->[0] )
       {
         $Canonical->{'description'} = $ret->{$dn}->{'description'}->[0];
       }
       push @{$Canonicals{'CanonicalTable'}}, $Canonical;
    }
    #now we return the result
    return \%Canonicals;
}

=item *
C<$MailTransports = ReadMailTransports($AdminPassword)>

  Dump the mail-server Mail Transport to a single hash
  @return hash Dumped settings (later acceptable by WriteMailTransport ())

  $MailTransports is a pointer to a hash containing the mail transport
  definitions.

  %MailTransports  = (
       'Changed'      => 0,
             Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

       'Transports'  => [],
             Poiter to an array containing the mail transport table entries.
		       
       'TLSSites'  => {},
             Poiter to an hash containing the mail transport TLS per site table entries.
       'SASLAccounts'  => {},
             Poiter to an hash containing the client side authentication accounts.
		       
   );
   
   Each element of the arry 'Transports' has following syntax:

   %Transport       = (
       'Destination'  => '',
           This field contains a search pattern for the mail destination.
           Patterns are tried in the order as listed below:

           user+extension@domain
              Mail for user+extension@domain is delivered through
              transport to nexthop.

           user@domain
              Mail for user@domain is delivered through transport
              to nexthop.

           domain
              Mail  for  domain is delivered through transport to
              nexthop.

           .domain
              Mail for  any  subdomain  of  domain  is  delivered
              through  transport  to  nexthop.  This applies only
              when the string transport_maps is not listed in the
              parent_domain_matches_subdomains configuration set-
              ting.  Otherwise, a domain name matches itself  and
              its subdomains.

           Note 1: the special pattern * represents any address (i.e.
           it functions as the wild-card pattern).

           Note 2:  the  null  recipient  address  is  looked  up  as
           $empty_address_recipient@$myhostname (default: mailer-dae-
           mon@hostname).

       'Nexthop'      => '',
           This field has the format transport:nexthop and shows how
           the mails for the corresponding destination will be
	   delivered.

           The transport field specifies the name of a mail  delivery
           transport (the first name of a mail delivery service entry
           in the Postfix master.cf file).
           
           The interpretation  of  the  nexthop  field  is  transport
           dependent. In the case of SMTP, specify host:service for a
           non-default server port, and use [host] or [host]:port  in
           order  to  disable MX (mail exchanger) DNS lookups. The []
           form is required when you specify an IP address instead of
           a hostname.
           
           A  null  transport  and  null nexthop result means "do not
           change": use the delivery transport and  nexthop  informa-
           tion  that  would  be used when the entire transport table
           did not exist.
           
           A non-null transport  field  with  a  null  nexthop  field
           resets the nexthop information to the recipient domain.
           
           A  null  transport  field with non-null nexthop field does
           not modify the transport information.

	   For a detailed description have a look in man 5 trnsport.
			  
    );

    %TLSSites       = {
    
       'TLSSite'          => ''
                The name or IP of the mail server (nexthop).

       'TLSMode'          => '',
	     You can set how TLS will be used for security. Possible values are:
		NONE    : don't use TLS.
		MAY     : TLS will used when offered by the server.
		MUST    : Only connection with TLS will be accepted.
		MUST_NOPEERMATCH  : Only connection with TLS will be accepted, but
		          no strict peername checking accours.
    };

    %SASLAccounts = {
       'Server1' => ['Account1','Password1'],
       'Server2' => ['Account2','Password2']
    }


    


EXAMPLE:

use MailServer;

    my $AdminPassword   = "VerySecure";

    my $MailTransorts   = [];

    if (! $MailTransorts = ReadMailTransports($AdminPassword) ) {
       print "ERROR in ReadMailTransports\n";
    } else {
       foreach my $Transport (@{$MailTransports->{'Transports'}}){
            print "Destination=> $Transport->{'Destination'}\n";
	    print "    Nexthop=> $Transport->{'Nexthop'}\n";
       }
       foreach my $TLSSite (keys %{$MailTransports->{'TLSSites'}}){
            print "TLSSite: $TLSSite => ";
	    print "TLSMode: $MailTransports->{'TLSSites'}->{$TLSSite}\n";
       }
       foreach my $SASLAccount (keys %{$MailTransports->{'SASLAccounts'}}){
            print "Nexthop: $SASLAccount => ";
	    print "Account: $MailTransports->{'SASLAccounts'}->{$SASLAccount}->[0] ";
	    print "Passord: $MailTransports->{'SASLAccounts'}->{$SASLAccount}->[1]\n";
       }
    }

=cut


BEGIN { $TYPEINFO{ReadMailTransports}  =["function", ["map", "string", "any"]  , "string"]; }
sub ReadMailTransports {
    my $self            = shift;
    my $AdminPassword   = shift;


    my %MailTransports  = ( 
                           'Changed'      => YaST::YCP::Boolean(0),
                           'Use'          => YaST::YCP::Boolean(1), 
                           'Transports'   => [], 
                           'TLSSites'     => {},
                           'SASLAccounts' => {}, 
                          );

    my %NeededServers  = ();

    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }
    my $SaslPaswd       = SCR->Read('.mail.postfix.saslpasswd.table');
    my $MainCf          = SCR->Read('.mail.postfix.main.table');
    my $transport_maps  = read_attribute($MainCf,'transport_maps');
    if($transport_maps !~ /ldap:\/etc\/postfix\/ldaptransport_maps.cf/)
    {
    	$MailTransports{'Use'} = YaST::YCP::Boolean(0);
    }

    my %SearchMap       = (
                               'base_dn'    => $ldapMap->{'mail_config_dn'},
                               'filter'     => "objectClass=suseMailTransport",
                               'scope'      => 2,
                               'map'        => 1,
                               'attributes' => ['suseMailTransportDestination',
			                        'suseMailTransportNexthop']
                          );

                             
    # Searching all the transport lists
    my $ret = SCR->Read('.ldap.search',\%SearchMap);

    # filling up our array
    foreach my $dn (keys %{$ret})
    {
       my $Transport       = {};
       $Transport->{'Destination'}     = $ret->{$dn}->{'suseMailTransportDestination'}->[0];
       if( $ret->{$dn}->{'suseMailTransportNexthop'}->[0] =~ /:/)
       {
         ($Transport->{'Transport'},$Transport->{'Nexthop'}) = split /:/,$ret->{$dn}->{'suseMailTransportNexthop'}->[0];
       }
       else
       {
         $Transport->{'Nexthop'}         = $ret->{$dn}->{'suseMailTransportNexthop'}->[0];
       }
       push @{$MailTransports{'Transports'}}, $Transport;
       if( $Transport->{'Nexthop'} =~ /\[(.*)\]/ )
       {
            $NeededServers{$1} = 1;
       }
       else
       {
            $NeededServers{$Transport->{'Nexthop'}} = 1;
       }
    }
    # looking for SASL Accounts 
    foreach my $Server (keys %NeededServers)
    {
       my $SASLAccount    = '';
       my $SASLPasswd     = '';
       #Looking the type of TSL
       my $tmp = read_attribute($SaslPaswd,$Server);
       if($tmp)
       {
           my @SASLAccount = split /:/, $tmp;
           $MailTransports{'SASLAccounts'}->{$Server} = \@SASLAccount;
       }
    }

    #Looking for TLS per site Accounts
    %SearchMap       = (
                               'base_dn'    => $ldapMap->{'mail_config_dn'},
                               'filter'     => "ObjectClass=suseTLSPerSiteContainer",
                               'scope'      => 2,
                               'map'        => 1,
                               'attributes' => [ 'suseTLSPerSiteMode',
						 'suseTLSPerSitePeer']
                       );
    # Searching all the transport lists
    $ret = SCR->Read('.ldap.search',\%SearchMap);

    # filling up our array
    foreach my $dn (keys %{$ret})
    {
       my $TLSMode         = $ret->{$dn}->{'suseTLSPerSiteMode'}->[0] || "NONE";
       my $TLSSite         = $ret->{$dn}->{'suseTLSPerSitePeer'}->[0] ;
       $MailTransports{'TLSSites'}->{$TLSSite} = $TLSMode;
    }
    
    #print STDERR Dumper(%MailTransports);

    #now we return the result
    return \%MailTransports;
}

=item *
C<boolean = WriteMailTransports($adminpwd,$MailTransports)>

 Write the mail server Mail Transport from a single hash.

 WARNING!

 All transport defintions not contained in the hash will be removed
 from the tranport table.

EXAMPLE:

use MailServer;

    my $AdminPassword   = "VerySecure";

    my %MailTransports  = ( 
                           'Changed' => '1',
                           'Transports'  => [] 
                          );
    my %Transport       = (
                             'Destination'  => 'dom.ain',
                             'Transport'    => 'smtp',
                             'Nexthop'      => '[mail.dom.ain]',
                             'TLS'          => 'MUST',
                             'Auth'         => 1,
                             'Account'      => 'user',
                             'Password'     => 'passwd'
                          );
    push @($MailTransports{Transports}), %Transport; 
    
    %Transport       = (
                             'Destination'  => 'my-domain.de',
                             'Nexthop'      => 'uucp:[mail.my-domain.de]',
                             'TLS'          => 'NONE',
                             'Auth'         => '0'
			);
    push @($MailTransports{Transports}), %Transport; 

    %Transport       = (
                             'Destination'  => 'my-old-domain.de',
                             'Nexthop'      => "error:I've droped this domain"
			);
    push @($MailTransports{Transports}), %Transport; 

    if( ! WriteMailTransports(\%Transports,$AdminPassword) ) {
        print "ERROR in WriteMailTransport\n";
    }

=cut

BEGIN { $TYPEINFO{WriteMailTransports}  =["function", "boolean", ["map", "string", "any"], "string"]; }
sub WriteMailTransports {
    my $self            = shift;
    my $MailTransports  = shift;
    my $AdminPassword   = shift;
   
    # Map for the Transport Entries
    my %Entries        = (); 
    my $ldapMap       = {}; 
    my $NeededServers  = {};

    # If no changes we haven't to do anything
    if(! $MailTransports->{'Changed'})
    {
         return $self->SetError( summary =>"Nothing to do",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    y2milestone("-- WriteMailTransports --");
#print STDERR Dumper($MailTransports);
    
    # Make LDAP Connection 
    $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }
    
    # Search hash to find all the Transport Objects
    my %SearchMap       = (
                               'base_dn' => $ldapMap->{'mail_config_dn'},
                               'filter'  => "objectClass=suseMailTransport",
                               'map'     => 1,
                               'scope'   => 2,
			       'attrs'   => ['suseMailTransportDestination' ]
                          );

    my $ret = SCR->Read('.ldap.search',\%SearchMap);

    # Now let's work
    foreach my $Transport (@{$MailTransports->{'Transports'}})
    {
       if( $Transport->{'Destination'} =~ /[^-\w\*\.\@\+]/ )
       {
	    return $self->SetError( summary     => 'Wrong Value for Mail Transport Destination. '.
	                                           'This field may contain only the charaters [-a-zA-Z.*@]',
				    code        => 'PARAM_CHECK_FAILED'
				  );
       }
       my $Destination =  $Transport->{'Destination'};
          $Destination =~ s#\+#\\+#;
       my $dn	= 'suseMailTransportDestination='.$Destination.','.$ldapMap->{'mail_config_dn'};
       $Entries{$dn}->{'suseMailTransportDestination'} = $Transport->{'Destination'};
       if(defined $Transport->{'Transport'} )
       {
          $Entries{$dn}->{'suseMailTransportNexthop'}  = $Transport->{'Transport'}.':'.$Transport->{'Nexthop'};
       }
       else
       {
          $Entries{$dn}->{'suseMailTransportNexthop'}  = $Transport->{'Nexthop'};
       }
       if( $Transport->{'Nexthop'} =~ /\[(.*)\]/ )
       {
            $NeededServers->{$1} = 1;
       }
       else
       {
            $NeededServers->{$Transport->{'Nexthop'}} = 1;
       }
    }


    #have a look if our table is OK. If not make it to work!
    my $MainCf             = SCR->Read('.mail.postfix.main.table');
    check_ldap_configuration('transport_maps',$ldapMap);
    check_ldap_configuration('smtp_tls_per_site',$ldapMap);
    if( $MailTransports->{Use} )
    {
	write_attribute($MainCf,'transport_maps','ldap:/etc/postfix/ldaptransport_maps.cf');
	write_attribute($MainCf,'smtp_tls_per_site','ldap:/etc/postfix/ldapsmtp_tls_per_site.cf');
    }
    else
    {
	write_attribute($MainCf,'transport_maps','');
	write_attribute($MainCf,'smtp_tls_per_site','');
    }

    # If there is no ERROR we do the changes
    # First we clean all the transport lists
    foreach my $key (keys %{$ret})
    {
       if(! SCR->Write('.ldap.delete',{'dn'=>$key}))
       {
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary     => "LDAP delete failed",
                                 code        => "SCR_WRITE_FAILED",
                                 description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }

    foreach my $dn (keys %Entries)
    {
       my $DN  = { 'dn' => $dn };
       my $tmp = { 'Objectclass'                  => [ 'suseMailTransport' ],
                   'suseMailTransportDestination' => $Entries{$dn}->{'suseMailTransportDestination'},
                   'suseMailTransportNexthop'     => $Entries{$dn}->{'suseMailTransportNexthop'}
                 };
       if(! SCR->Write('.ldap.add',$DN,$tmp))
       {
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary     => "LDAP add failed",
                                 code        => "SCR_WRITE_FAILED",
                                 description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }
    # Done Create new Transports

    #Creating the new TLS per Site entries
    %Entries = ();
    foreach my $TLSSite (keys %{$MailTransports->{'TLSSites'}})
    {
       if( ! defined $NeededServers->{$TLSSite} )
       {
             next;
       }
       my $dn	= 'suseTLSPerSitePeer='.$TLSSite.','.$ldapMap->{'mail_config_dn'};
       $Entries{$dn}->{'suseTLSPerSiteMode'}           = 'NONE';

       if($MailTransports->{'TLSSites'}->{$TLSSite} =~ /NONE|MAY|MUST|MUST_NOPEERMATCH/)
       {
            $Entries{$dn}->{'suseTLSPerSitePeer'}      = $TLSSite;
            $Entries{$dn}->{'suseTLSPerSiteMode'}      = $MailTransports->{'TLSSites'}->{$TLSSite};
       }
       else
       {
	    return $self->SetError( summary     => 'Wrong Value for suseTLSPerSiteMode',
				    code        => 'PARAM_CHECK_FAILED'
				  );
       }
    }
    # Search hash to find all the TLSSites Objects
    %SearchMap       = (
                               'base_dn' => $ldapMap->{'mail_config_dn'},
                               'filter'  => "objectClass=suseTLSPerSiteContainer",
                               'map'     => 1,
                               'scope'   => 2,
			       'attrs'   => []
                          );
    $ret = SCR->Read('.ldap.search',\%SearchMap);
    # First we clean all the TLSSites
    foreach my $key (keys %{$ret})
    {
       if(! SCR->Write('.ldap.delete',{'dn'=>$key}))
       {
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary     => "LDAP delete failed",
                                 code        => "SCR_WRITE_FAILED",
                                 description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }
    #And now we add the new TLSSites
    foreach my $dn (keys %Entries)
    {
       my $DN  = { 'dn' => $dn };
       my $tmp = { 'Objectclass'                  => [ 'suseTLSPerSiteContainer' ],
                   'suseTLSPerSiteMode'           => $Entries{$dn}->{'suseTLSPerSiteMode'},
                   'suseTLSPerSitePeer'           => $Entries{$dn}->{'suseTLSPerSitePeer'}
                 };
       if(! SCR->Write('.ldap.add',$DN,$tmp))
       {
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary     => "LDAP add failed",
                                 code        => "SCR_WRITE_FAILED",
                                 description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }

    # Now we create the new SaslPasswd entries
    # We have to save the entry for the relay host
    # We'll need the sasl passwords entries
    my $OldSaslPasswd = SCR->Read('.mail.postfix.saslpasswd.table');
    my $SaslPasswd    = SCR->Read('.mail.postfix.saslpasswd.table');

    my $RelayHost = read_attribute($MainCf,'relayhost');
    foreach(@{$OldSaslPasswd})
    {
      if($_->{"key"} eq $RelayHost)
      {
         next;
      }
      elsif( ! defined $MailTransports->{'SASLAccounts'}->{$_->{"key"}})
      {
         write_attribute($SaslPasswd,$_->{"key"},"");
      }
    }
    foreach(keys %{$MailTransports->{'SASLAccounts'}})
    {
         my $Account  = $MailTransports->{'SASLAccounts'}->{$_}->[0];
         my $Password = $MailTransports->{'SASLAccounts'}->{$_}->[1];
         write_attribute($SaslPasswd,$_,"$Account:$Password");
    }
    if( scalar(keys(%{$MailTransports->{'SASLAccounts'}})) > 0 )
    {
         write_attribute($MainCf,'smtp_sasl_auth_enable','yes');
         write_attribute($MainCf,'smtp_sasl_password_maps','hash:/etc/postfix/sasl_passwd');
    }
    write_attribute($MainCf,'smtp_sasl_security_options','noanonymous');

    SCR->Write('.mail.postfix.saslpasswd.table',$SaslPasswd);
    SCR->Write('.mail.postfix.saslpasswd',undef);
    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.mail.postfix.main',undef);

    return 1;
}

=item *
C<$MailPrevention = ReadMailPrevention($adminpwd)>

 Dump the mail-server prevention to a single hash
 @return hash Dumped settings (later acceptable by WriteMailPrevention())

 Postfix offers a variety of parameters that limit the delivery of 
 unsolicited commercial email (UCE). 

 By default, the Postfix SMTP server will accept mail only from or to the
 local network or domain, or to domains that are hosted by Postfix, so that
 your system can't be used as a mail relay to forward bulk mail from random strangers.

 There is a lot of combination of the postfix configuration parameter 
 you can set. To make the setup easier we have defined three kind of predefined
 settings: 
   off:
        1. Accept connections from all clients even if the client IP address has no 
           PTR (address to name) record in the DNS. 
        2. Accept all eMails has RCPT a local destination or the client is in the
           local network.
        3. Mail adresses via access table can be rejected.
   medium:
        1. Accept connections from all clients even if the client IP address has no 
           PTR (address to name) record in the DNS. 
        2. Accept all eMails has RCPT a local destination and the sender domain is
           a valid domain. Furthermore mails from clients from local network will
           be accepted.
        3. 
   hard:

 $MailPrevention is a pointer to a hash containing the mail server
 basic prevention settings. This hash has following structure:


 my %MailPrevention      = (
           'Changed'               => 0,
             Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

           'BasicProtection'       => 'hard',
           'RBLList'               => [],
           'AccessList'            => [],
           'VirusScanning'         => 1,
           'VSCount'               => 10
           'SpamLearning'          => 1
                          );

   AccessList is a pointer to an array of %AccessEntry hashes.

 my %AccessEntry         = (  'ClientAddress' => '',
                              'ClientAccess'  => ''
			   );

EXAMPLE:

use MailServer;

    my $AdminPassword   = "VerySecure";
    my $MailPrevention  = [];

    if( $MailPrevention = ReadMailPrevention($AdminPassword) ) {
        print "Basic BasicProtection : $MailPrevention->{BasicProtection}\n";
        foreach(@{$MailPrevention->{RBLList}}) {
          print "Used RBL Server: $_\n";
        }
        foreach(@{$MailPrevention->{AccessList}}) {
          print "Access for  $_{MailClient} is $_{MailAction}\n";
        }
        if($MailPrevention->{VirusScanning}){
          print "Virus scanning is activated\n";
        } else {
          print "Virus scanning isn't activated\n";
        }
    } else {
        print "ERROR in ReadMailPrevention\n";
    }

=cut

BEGIN { $TYPEINFO{ReadMailPrevention}  =["function", "any", "string" ]; }
sub ReadMailPrevention {
    my $self            = shift;
    my $AdminPassword   = shift;

    my %MailPrevention  = (
                               'Changed'                    => YaST::YCP::Boolean(0),
			       'BasicProtection'            => 'hard',
			       'RBLList'                    => [],
			       'AccessList'                 => [],
			       'VirusScanning'              => YaST::YCP::Boolean(0),
			       'VSCount'                    => YaST::YCP::Integer(5),
			       'SpamLearning'               => YaST::YCP::Boolean(0)
                          );

    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }

    # First we read the main.cf and master.cf 
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    if( ! SCR->Read('.mail.postfix.mastercf') )
    {
         return $self->SetError( summary =>"Couln't open master.cf",
                                 code    => "PARAM_CHECK_FAILED" );
    }

    # We ar looking for the BasicProtection Basic Prevention
    my $smtpd_helo_restrictions = read_attribute($MainCf,'smtpd_helo_restrictions');
    if( $smtpd_helo_restrictions !~ /reject_invalid_hostname/ )
    {
       my $smtpd_helo_required  = read_attribute($MainCf,'smtpd_helo_required');
       if( $smtpd_helo_required =~ /no/ )
       {
         $MailPrevention{'BasicProtection'} =  'off';    
       }
       else
       {
         $MailPrevention{'BasicProtection'} =  'medium';
       }
    }

    # If the BasicProtection Basic Prevention is not off we collect the list of the RBL hosts
    if($MailPrevention{'BasicProtection'} ne 'off')
    {
       my $smtpd_client_restrictions = read_attribute($MainCf,'smtpd_client_restrictions');
       foreach(split /, |,/, $smtpd_client_restrictions)
       {
          if(/reject_rbl_client (.*)/)
	  {
	    push @{$MailPrevention{'RBLList'}}, $1;
	  }
       }
    }

    #Now we read the access table
    my %SearchMap = (
                   'base_dn' => $ldapMap->{'mail_config_dn'},
                   'filter'  => "ObjectClass=suseMailAccess",
                   'scope'   => 2,
                   'attrs'   => ['suseMailClient','suseMailAction']
                 );
    my $ret = SCR->Read('.ldap.search',\%SearchMap);
    foreach my $entry (@{$ret})
    {  
       my $AccessEntry = {};
       $AccessEntry->{'MailClient'} = $entry->{'suseMailClient'}->[0];
       $AccessEntry->{'MailAction'} = $entry->{'suseMailAction'}->[0];
       push @{$MailPrevention{'AccessList'}}, $AccessEntry;
    }

    # Now we looking for if vscan (virusscanning) is started.
    my $vscanin = SCR->Execute('.mail.postfix.mastercf.findService',
		{ 'service' => 'localhost:10025',
		  'command' => 'smtpd'} );
    my $vscanout = SCR->Execute('.mail.postfix.mastercf.findService',
		{ 'service' => 'amavis',
		  'command' => 'lmtp'} );
    my $content_filter = read_attribute($MainCf,'content_filter');

    if( $content_filter eq 'amavis:[127.0.0.1]:10024' && $vscanin && $vscanout)
    {
        $MailPrevention{'VirusScanning'} = YaST::YCP::Boolean(1);
        if( ! open(IN,$aconf) )
        {
           return "Error: $!";
        }
        my @ACONF = <IN>;
        close(IN);
        my $ismax = 0;
        foreach ( @ACONF )
        {
        	s/\s+//g;
		if ( /^\$max_servers=(\d+)/ )
		{
		    $MailPrevention{'VSCount'} = YaST::YCP::Integer($1);
		}
		$ismax = 1;
        }
        if( !$ismax )
        {
            $MailPrevention{'VSCount'} = YaST::YCP::Integer(2);
        }
    }
    # make IMAP connection
    my $imap = new Net::IMAP($imaphost, Debug => 0);
    if( $imap )
    {
        $ret = $imap->login($imapadm, $AdminPassword);
	if($$ret{Status} eq "ok") {
	    $ret = $imap->select('NewSpam'); 
	    if( $ret->{Status} eq 'ok' )
	    {
	        $MailPrevention{'SpamLearning'} = YaST::YCP::Boolean(1);
	    }
	}
	$imap->logout();
    }
    
    return \%MailPrevention;
}

##
 # Write the mail-server Mail Prevention from a single hash
 #
BEGIN { $TYPEINFO{WriteMailPrevention}  =["function", "boolean", ["map", "string", "any"], "string"]; }
sub WriteMailPrevention {
    my $self            = shift;
    my $MailPrevention  = shift;
    my $AdminPassword   = shift;

    if(! $MailPrevention->{'Changed'})
    {
         return $self->SetError( summary =>"Nothing to do",
                                 code    => "PARAM_CHECK_FAILED" );
    }
   
    y2milestone("-- WriteMailPrevention --");
    #print STDERR Dumper( $MailPrevention );
    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }

    # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    if( ! SCR->Read('.mail.postfix.mastercf') )
    {
         return $self->SetError( summary =>"Couln't open master.cf",
                                 code    => "PARAM_CHECK_FAILED" );
    }

    #Collect the RBL host list
    my $clnt_restrictions = '';
    foreach(@{$MailPrevention->{'RBLList'}})
    {
      if($clnt_restrictions eq '')
      {
          $clnt_restrictions="reject_rbl_client $_";
      }
      else
      {
          $clnt_restrictions="$clnt_restrictions, reject_rbl_client $_";
      }
    }

    my $smtpd_recipient_restrictions = read_attribute($MainCf,'smtpd_recipient_restrictions');
    if( $smtpd_recipient_restrictions =~ /permit_sasl_authenticated/)
    {
        $smtpd_recipient_restrictions = "permit_sasl_authenticated, ";
    }
    else
    {
        $smtpd_recipient_restrictions = "";
    }
    write_attribute($MainCf,'smtpd_recipient_restrictions',$smtpd_recipient_restrictions.'permit_auth_destination, permit_mynetworks, reject_unauth_destination, reject');
    if($MailPrevention->{'BasicProtection'} eq 'hard')
    {
      #Write hard settings 
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:/etc/postfix/ldapaccess.cf, reject_unknown_sender_domain');   
       write_attribute($MainCf,'smtpd_helo_required','yes');   
       write_attribute($MainCf,'smtpd_helo_restrictions','permit_mynetworks, reject_invalid_hostname');   
       write_attribute($MainCf,'strict_rfc821_envelopes','yes');   
       write_attribute($MainCf,'local_recipient_maps','$alias_maps, ldap:/etc/postfix/ldaplocal_recipient_maps.cf');
       if( $clnt_restrictions ne '')
       {
          write_attribute($MainCf,'smtpd_client_restrictions',"permit_mynetworks, $clnt_restrictions, ldap:/etc/postfix/ldapaccess.cf, reject_unknown_client");
       }
       else
       {
          write_attribute($MainCf,'smtpd_client_restrictions','permit_mynetworks, ldap:/etc/postfix/ldapaccess.cf, reject_unknown_client');
       }
    }
    elsif($MailPrevention->{'BasicProtection'} eq 'medium')
    {
      #Write medium settings  
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:/etc/postfix/ldapaccess.cf, reject_unknown_sender_domain');   
       write_attribute($MainCf,'smtpd_helo_required','yes');   
       write_attribute($MainCf,'smtpd_helo_restrictions','');   
       write_attribute($MainCf,'strict_rfc821_envelopes','no');   
       write_attribute($MainCf,'local_recipient_maps','$alias_maps, ldap:/etc/postfix/ldaplocal_recipient_maps.cf');
       if( $clnt_restrictions ne '')
       {
          write_attribute($MainCf,'smtpd_client_restrictions',"$clnt_restrictions, ldap:/etc/postfix/ldapaccess.cf");
       }
       else
       {
          write_attribute($MainCf,'smtpd_client_restrictions','ldap:/etc/postfix/ldapaccess.cf');
       }
    }
    elsif($MailPrevention->{'BasicProtection'} eq 'off')
    {
      # Write off settings  
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:/etc/postfix/ldapaccess.cf');   
       write_attribute($MainCf,'smtpd_helo_required','no');   
       write_attribute($MainCf,'smtpd_helo_restrictions','');   
       write_attribute($MainCf,'strict_rfc821_envelopes','no');   
       write_attribute($MainCf,'smtpd_client_restrictions','ldap:/etc/postfix/ldapaccess.cf');
       write_attribute($MainCf,'local_recipient_maps','$alias_maps, ldap:/etc/postfix/ldaplocal_recipient_maps.cf');
    }
    else
    {
      # Error no such value
         return $self->SetError( summary =>"Unknown BasicProtection mode. Allowed values are: hard, medium, off",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    #Now we have a look on the access table
    my %SearchMap = (
                   'base_dn' => $ldapMap->{'mail_config_dn'},
                   'filter'  => "objectClass=suseMailAccess",
                   'scope'   => 2,
                   'map'     => 1
                 );
    my $ret = SCR->Read('.ldap.search',\%SearchMap);
    #First we clean the access table
    foreach my $key (keys %{$ret})
    {
       if(! SCR->Write('.ldap.delete',{'dn'=>$key}))
       {
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary     => "LDAP delete failed",
                                 code        => "SCR_WRITE_FAILED",
                                 description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }

    #Now we write the new table
#print STDERR Dumper([$MailPrevention->{'AccessList'}]);
    foreach my $entry (@{$MailPrevention->{'AccessList'}})
    {
       my $dn  = { 'dn' => "suseMailClient=".$entry->{'MailClient'}.','. $ldapMap->{'mail_config_dn'}};
       my $tmp = { 'suseMailClient'   => $entry->{'MailClient'},
                   'suseMailAction'   => $entry->{'MailAction'},
                   'ObjectClass'      => ['suseMailAccess']
                 };
       if(! SCR->Write('.ldap.add',$dn,$tmp))
       {
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary => "LDAP add failed",
                               code => "SCR_INIT_FAILED",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }

    SCR->Read('.mail.postfix.mastercf');
    if( $MailPrevention->{'VirusScanning'} )
    {
	$MailPrevention->{'VSCount'} = 5 if( ! defined $MailPrevention->{'VSCount'});
	my $err = activate_virus_scanner($MailPrevention->{'VSCount'});
	if( $err ne "" )
	{
	    return $self->SetError(summary => "activating virus scanner failed",
				   code => "VIRUS_SCANNER_FAILED",
				   description => "activating the virus scanner failed: $err");
	}
	# This is only for systems updated from SLES10
		my $smtps = SCR->Execute('.mail.postfix.mastercf.findService',
					 { 'service' => 'smtps', 'command' => 'smtpd' });
		if( ref($smtps) eq 'ARRAY' && defined $smtps->[0]->{options} )
		{
		    my $opts = $smtps->[0]->{options};
		    if ( defined $opts->{'content_filter'} )
		    {
			    delete $opts->{'content_filter'};
			    SCR->Execute('.mail.postfix.mastercf.modifyService',
					 { 'service' => 'smtps',
					   'command' => 'smtpd',
					   'maxproc' => '-',
					   'options' => $opts } );
		    }
		}
		my $smtp = SCR->Execute('.mail.postfix.mastercf.findService',
					 { 'service' => 'smtp', 'command' => 'smtpd' });
		if( ref($smtp) eq 'ARRAY' && defined $smtp->[0]->{options} )
		{
		    my $opts = $smtp->[0]->{options};
		    if ( defined $opts->{'content_filter'} )
		    {
			    delete $opts->{'content_filter'};
			    SCR->Execute('.mail.postfix.mastercf.modifyService',
					 { 'service' => 'smtp',
					   'command' => 'smtpd',
					   'maxproc' => '-',
					   'options' => $opts } );
		    }
		}
	# End This is only for systems updated from SLES10
	if( SCR->Execute('.mail.postfix.mastercf.findService',
	    { 'service' => 'localhost:10025', 'command' => 'smtpd' }))
	{
	    SCR->Execute('.mail.postfix.mastercf.deleteService',
	        { 'service' => 'localhost:10025', 'command' => 'smtpd' });
	}
	if( SCR->Execute('.mail.postfix.mastercf.findService',
	    { 'service' => 'amavis', 'command' => 'lmtp' }))
	{
	    SCR->Execute('.mail.postfix.mastercf.deleteService',
	        { 'service' => 'amavis', 'command' => 'lmtp' });
	}
	# create smtpd pocess for getting back the emails
        SCR->Execute('.mail.postfix.mastercf.addService',
		{ 'service' => 'amavis',
		  'command' => 'lmtp',
		  'type'    => 'unix',
		  'private' => '-',
		  'unpriv'  => '-',
		  'chroot'  => '-',
		  'wakeup'  => '-',
		  'maxproc' => $MailPrevention->{'VSCount'},
		  'options' => { lmtp_data_done_timeout     => 1200,
				 lmtp_send_xforward_command => 'yes',
				 disable_dns_lookups        => 'yes',
				 max_use                    => 20 } } );
        SCR->Execute('.mail.postfix.mastercf.addService',
		{ 'service' => 'localhost:10025',
		  'command' => 'smtpd',
		  'type'    => 'inet',
		  'private' => 'n',
		  'unpriv'  => '-',
		  'chroot'  => 'n',
		  'wakeup'  => '-',
		  'maxproc' => '-',
		  'options' => {  content_filter => '',
				  local_recipient_maps => '',
				  relay_recipient_maps => '',
				  smtpd_delay_reject => 'no',
				  smtpd_restriction_classes => '',
				  smtpd_client_restrictions => '',
				  smtpd_helo_restrictions => '',
				  smtpd_sender_restrictions => '',
				  smtpd_recipient_restrictions => 'permit_mynetworks,reject',
				  smtpd_data_restrictions => 'reject_unauth_pipelining',
				  smtpd_end_of_data_restrictions => '',
				  mynetworks => '127.0.0.0/8',
				  smtpd_error_sleep_time => '0',
				  smtpd_soft_error_limit => '1001',
				  smtpd_hard_error_limit => '1000',
				  smtpd_client_connection_count_limit => '0',
				  smtpd_client_connection_rate_limit => '0',
				  receive_override_options => 'no_header_body_checks,no_unknown_recipient_checks'
		  		} 
		} );
       write_attribute($MainCf,'content_filter','amavis:[127.0.0.1]:10024');   
    }
    else
    {
	SCR->Execute('.mail.postfix.mastercf.deleteService',
	    { 'service' => 'localhost:10025', 'command' => 'smtpd' });
	SCR->Execute('.mail.postfix.mastercf.deleteService',
	    { 'service' => 'amavis', 'command' => 'lmtp' });
	write_attribute($MainCf,'content_filter','');   
	
	Service->Stop('amavis');
	Service->Stop('clamd');
	Service->Disable('amavis');
	Service->Disable('clamd');
    }

    # now we looks if the ldap entries in the main.cf for the access table are OK.
    check_ldap_configuration('local_recipient_maps',$ldapMap);
    check_ldap_configuration('access',$ldapMap);
    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.mail.postfix.main',undef);
    SCR->Write('.mail.postfix.mastercf',undef);

    # make IMAP connection
    my $imap = new Net::IMAP($imaphost, Debug => 0);
    if( $imap )
    {
        my $ret = $imap->login($imapadm, $AdminPassword);
	if($$ret{Status} eq "ok")
	{
    	    if( $MailPrevention->{'SpamLearning'} )
	    {
	        $ret = $imap->create('NewSpam'); 
	        $ret = $imap->create('NoSpam'); 
		$ret = $imap->setacl('NewSpam', $imapadm, "lrswipkxtea");
		$ret = $imap->setacl('NoSpam',  $imapadm, "lrswipkxtea");
		$ret = $imap->setacl('NewSpam', 'anyone', "lrswi");
		$ret = $imap->setacl('NoSpam',  'anyone', "lsi");
		my $lernspam = '#!/bin/bash
LOG=/var/log/lern-spam
/usr/share/oss/tools/oss_date.sh >> $LOG
if [ ! -d /var/spool/imap/NewSpam ]
then
  exit
fi

setfacl -m u:vscan:rx /var/spool/imap /var/spool/imap/{NoSpam,NewSpam}
setfacl -m m::rx /var/spool/imap /var/spool/imap/{NoSpam,NewSpam}

/usr/bin/sa-learn --sync --dbpath /var/spool/amavis/.spamassassin/
(
for i in `ls /var/spool/imap/NewSpam/[0-9]* 2> /dev/null`
do
   setfacl -m user:vscan:r-x $i
   echo $i 
   /usr/bin/sa-learn --spam --dbpath /var/spool/amavis/.spamassassin/ $i
   rm $i
done
) >> $LOG  2>&1
su - cyrus -c "reconstruct NewSpam" &>/dev/null

(
for i in `ls /var/spool/imap/NoSpam/[0-9]* 2> /dev/null`
do
   setfacl -m user:vscan:r-x $i
   echo $i 
   /usr/bin/sa-learn --ham --dbpath /var/spool/amavis/.spamassassin/ $i
   rm $i
done
) >> $LOG  2>&1
su - cyrus -c "reconstruct NoSpam" &>/dev/null
chown -R vscan /var/spool/amavis/.spamassassin/

setfacl -b /var/spool/imap /var/spool/imap/{NoSpam,NewSpam}
';
		SCR->Write(".target.string","/etc/cron.hourly/lern-spam",$lernspam);
		SCR->Write(".target.bash","chmod 755 /etc/cron.hourly/lern-spam");
	    }
	    $imap->logout();
	}
	else
	{
	    SCR->Write(".target.bash","test -e /etc/cron.hourly/lern-spam && rm /etc/cron.hourly/lern-spam");
	    $ret = $imap->delete('NewSpam'); 
	    $ret = $imap->delete('NoSpam'); 
	    $imap->logout();
	}
    }
    return  1;
}

=item *
C<$MailRelaying = ReadMailRelaying($adminpwd)>

 Dump the mail-server server side relay settings to a single hash
 @return hash Dumped settings (later acceptable by WriteMailRelaying ())

 $MailRelaying is a pointer to a hash containing the mail server
 relay settings. This hash has following structure:

 %MailRelaying    = (
           'Changed'               => 0,
             Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

           'TrustedNetworks' => [],
             An array of trusted networks/hosts addresses

           'RequireSASL'     => 1,
             Show if SASL authentication is required for sending external eMails.
 
           'SMTPDTLSMode'    => 'use',
             Shows how TLS will be used for smtpd connection.
             Avaiable values are:
             'none'      : no TLS will be used.
             'use'       : TLS will be used if the client wants.
             'enfoce'    : TLS must be used.
             'auth_only' : TLS will be used only for SASL authentication.

           'UserRestriction' => 0
             If UserRestriction is set, there is possible to make user/group based 
             restrictions for sending and getting eMails. Strickt authotentication
             is requiered. To do so an 2nd interface for sending eMails for internal
             clients will be set up. The system administrator have to care that the
             other interface (external interface) can not be accessed from the internal
             clients
                          );

  

=cut

BEGIN { $TYPEINFO{ReadMailRelaying}  =["function", "any", "string" ]; }
sub ReadMailRelaying {
    my $self            = shift;
    my $AdminPassword   = shift;
    my %MailRelaying    = (
                                'Changed'         => YaST::YCP::Boolean(0),
                                'TrustedNetworks' => [],
                                'RequireSASL'     => 0,
                                'SMTPDTLSMode'    => 'use',
                                'UserRestriction' => 0
                          );

    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }

    # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    # Now we look if there are manual inclued mynetworks entries
    # my $TrustedNetworks    = read_attribute($MainCf,'mynetworks');
    my $TrustedNetworks = `postconf -h mynetworks`;
    chomp $TrustedNetworks;
    foreach(split /, |,| /, $TrustedNetworks)
    { 
       if(! /ldapmynetworks/ && /\w+/)
       {
          push @{$MailRelaying{'TrustedNetworks'}}, $_;
       }
    }

    #Now we have a look on the mynetworks ldaptable
#    my %SearchMap = (
##                   'base_dn' => $ldapMap->{'mail_config_dn'},
#                   'filter'  => "ObjectClass=suseMailMyNetorks",
#                   'attrs'   => ['suseMailClient']
#                 );
#    my $ret = SCR->Read('.ldap.search',\%SearchMap);
#
#    foreach my $entry (@{$ret}){
#        foreach(@{$entry->{'suseMailClient'}}) {
#          push @{$MailRelaying{'TrustedNetworks'}}, $_;
#        }
#    }

    my $smtpd_recipient_restrictions = read_attribute($MainCf,'smtpd_recipient_restrictions');
    my $smtpd_sasl_auth_enable       = read_attribute($MainCf,'smtpd_sasl_auth_enable');
    my $smtpd_use_tls                = read_attribute($MainCf,'smtpd_use_tls');
    my $smtpd_enforce_tls            = read_attribute($MainCf,'smtpd_enforce_tls');
    my $smtpd_tls_auth_only          = read_attribute($MainCf,'smtpd_tls_auth_only');
    if($smtpd_use_tls eq 'no')
    {
       $MailRelaying{'SMTPDTLSMode'} = 'none';
    }
    if($smtpd_enforce_tls eq 'yes')
    {
       $MailRelaying{'SMTPDTLSMode'} = 'enforce';
    }
    if($smtpd_tls_auth_only eq 'yes')
    {
       $MailRelaying{'SMTPDTLSMode'} = 'auth_only';
    } 
    if($smtpd_sasl_auth_enable eq 'yes')
    {
       $MailRelaying{'RequireSASL'}  = 1;
       if( $smtpd_recipient_restrictions !~ /permit_sasl_authenticated/)
       {
         $self->SetError( summary => 'Postfix configuration mistake: smtpd_sasl_auth_enable is yes, but '.
                                     'smtpd_recipient_restrictions doesn\'t contain permit_sasl_authenticated.',
                                 code    => "PARAM_CHECK_FAILED" );
       }                          
    }

#print STDERR Dumper(%MailRelaying);
    return \%MailRelaying;
}

##
 # Write the mail-server server side relay settings  from a single hash
 #
BEGIN { $TYPEINFO{WriteMailRelaying}  =["function", "boolean",["map", "string", "any"], "string"]; }
sub WriteMailRelaying {
    my $self            = shift;
    my $MailRelaying    = shift;
    my $AdminPassword   = shift;
   
    #If nothing to do we don't do antithing
    if(! $MailRelaying->{'Changed'})
    {
         return $self->SetError( summary =>"Nothing to do",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    y2milestone("-- WriteMailRelaying --");
    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }

   # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    # now we collent the trusted networks;
    my $TrustedNetworks    = '';
    foreach(@{$MailRelaying->{'TrustedNetworks'}})
    {
      if( $TrustedNetworks ne '' )
      {
        $TrustedNetworks = $TrustedNetworks.', '.$_
      }
      else
      {
        $TrustedNetworks = $_;
      }
    }
    write_attribute($MainCf,'mynetworks',$TrustedNetworks);

    my $smtpd_recipient_restrictions = read_attribute($MainCf,'smtpd_recipient_restrictions');      
    if($MailRelaying->{'RequireSASL'})
    {
       write_attribute($MainCf,'smtpd_sasl_auth_enable','yes');
      if( $smtpd_recipient_restrictions !~ /permit_sasl_authenticated/)
      {
          $smtpd_recipient_restrictions = 'permit_sasl_authenticated, '.$smtpd_recipient_restrictions;
          write_attribute($MainCf,'smtpd_recipient_restrictions',$smtpd_recipient_restrictions);
      }
    }
    else
    {
      if( $smtpd_recipient_restrictions =~ s/permit_sasl_authenticated//)
      {
        $smtpd_recipient_restrictions =~ s/,\s*,/,/;
	$smtpd_recipient_restrictions =~ s/^\s*,\s*//;
        write_attribute($MainCf,'smtpd_recipient_restrictions',$smtpd_recipient_restrictions);
      }
      write_attribute($MainCf,'smtpd_sasl_auth_enable','no');
    }

    #now we write TLS settings for the smtpd daemon
    if($MailRelaying->{'SMTPDTLSMode'} eq 'none')
    {
        write_attribute($MainCf,'smtpd_use_tls','no');
        write_attribute($MainCf,'smtp_enforce_tls','no');
        write_attribute($MainCf,'smtpd_tls_auth_only','no');
    }
    elsif($MailRelaying->{'SMTPDTLSMode'} eq 'use')
    {
        write_attribute($MainCf,'smtpd_use_tls','yes');
        write_attribute($MainCf,'smtp_enforce_tls','no');
        write_attribute($MainCf,'smtpd_tls_auth_only','no');
    }
    elsif($MailRelaying->{'SMTPDTLSMode'} eq 'enforce')
    {
        write_attribute($MainCf,'smtpd_use_tls','yes');
        write_attribute($MainCf,'smtp_enforce_tls','yes');
        write_attribute($MainCf,'smtpd_tls_auth_only','no');
    }
    elsif($MailRelaying->{'SMTPDTLSMode'} eq 'auth_only')
    {
        write_attribute($MainCf,'smtpd_use_tls','yes');
        write_attribute($MainCf,'smtp_enforce_tls','no');
        write_attribute($MainCf,'smtpd_tls_auth_only','yes');
    }
    else
    {
         return $self->SetError( summary => 'Bad value for SMTPDTLSMode. Avaiable values are:'.
                                            "\nnone use enforce auth_only",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    # Searching for the tlsmanager service
    if( ! SCR->Read('.mail.postfix.mastercf') )
    {
       return $self->SetError( summary =>"Couln't open master.cf",
                               code    => "PARAM_CHECK_FAILED" );
    }
    my $tlsmgr = SCR->Execute('.mail.postfix.mastercf.findService',
                   { 'service' => 'tlsmgr',
                     'command' => 'tlsmgr' });
    if($MailRelaying->{'SMTPDTLSMode'} ne 'none')
    {
      my $size = SCR->Read(".target.size", '/etc/ssl/servercerts/servercert.pem');
      if ($size <= 0)
      {
          return $self->SetError(summary => "Common server certificate not found.",
                                 code => "PARAM_CHECK_FAILED");
      }
      $size = SCR->Read(".target.size", '/etc/ssl/servercerts/serverkey.pem');
      if ($size <= 0)
      {
          return $self->SetError(summary => "Common private key not found.",
                                 code => "PARAM_CHECK_FAILED");
      }
      write_attribute($MainCf,'smtpd_tls_cert_file','/etc/ssl/servercerts/servercert.pem');
      write_attribute($MainCf,'smtpd_tls_key_file','/etc/ssl/servercerts/serverkey.pem');
      if(SCR->Read(".target.size", '/etc/ssl/certs/YaST-CA.pem') > 0)
      {
          #write_attribute($MainCf,'smtpd_tls_CAfile','/etc/ssl/certs/YaST-CA.pem');
          write_attribute($MainCf,'smtpd_tls_CApath','/etc/ssl/certs');
      }
      if(! defined $tlsmgr )
      {
           SCR->Execute('.mail.postfix.mastercf.addService',
	   { 'service' => 'tlsmgr',
	     'type'    => 'unix',
	     'private' => '-',
	     'unpriv'  => '-',
	     'chroot'  => 'n',
	     'wakeup'  => '1000?',
	     'maxproc' => '1',
	     'command' => 'tlsmgr' });
      }
    }
    else
    {
      if( defined $tlsmgr )
      {
         SCR->Execute('.mail.postfix.mastercf.deleteService', {'service' => 'tlsmgr','command' => 'tlsmgr'});
      }
    }
    SCR->Write('.mail.postfix.mastercf',undef);
    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.mail.postfix.main',undef);

    return 1;

}

##
BEGIN { $TYPEINFO{ReadMailLocalDelivery}  =["function", "any", "string"]; }
sub ReadMailLocalDelivery {
    my $self            = shift;
    my $AdminPassword   = shift;
    my %MailLocalDelivery = (
                                'Changed'         => YaST::YCP::Boolean(0),
                                'Type'            => '',
                                'MailboxSizeLimit'=> 0,
                                'FallBackMailbox' => '',
                                'SpoolDirectory'  => '',
                                'QuotaLimit'      => 90,
                                'HardQuotaLimit'  => 0,
                                'ImapIdleTime'    => 30,
                                'PopIdleTime'     => 10,
			        'Security'        => 0,
                                'AlternateNameSpace'  => ''
                            );

    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }

   # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    my $MailboxCommand     = read_attribute($MainCf,'mailbox_command');
    my $MailboxTransport   = read_attribute($MainCf,'mailbox_transport');
    my $MailboxSizeLimit   = read_attribute($MainCf,'mailbox_size_limit');
    my $HomeMailbox        = read_attribute($MainCf,'home_mailbox');
    my $MailSpoolDirectory = read_attribute($MainCf,'mail_spool_directory');
    my $LocalTransport     = read_attribute($MainCf,'local_transport');
    my $mydestination      = read_attribute($MainCf,'mydestination');
    
    if( $mydestination eq '' )
    {
	$MailLocalDelivery{'Type'}      = 'none';
    }
    elsif( $MailboxCommand eq '' && $MailboxTransport eq '')
    {
       $MailLocalDelivery{'Type'}      = 'local';
       if( $MailboxSizeLimit =~ /^\d+$/ )
       {
            $MailLocalDelivery{'MailboxSizeLimit'}  = int(($MailboxSizeLimit + 1023) / 1024);
       } 
       if( $HomeMailbox ne '' )
       {
           $MailLocalDelivery{'SpoolDirectory'} = '$HOME/'.$HomeMailbox;
       }
       elsif ( $MailSpoolDirectory ne '' )
       {
           $MailLocalDelivery{'SpoolDirectory'} = $MailSpoolDirectory;
       }
       else
       {
           $MailLocalDelivery{'SpoolDirectory'} = '/var/spool/mail';
       }
    }
    elsif($MailboxCommand =~ /\/usr\/bin\/procmail/)
    {
        $MailLocalDelivery{'Type'} = 'procmail';
    }
    elsif($MailboxTransport =~ /lmtp:unix:\/var\/lib\/imap\/socket\/lmtp/)
    {
        $MailLocalDelivery{'Type'} = 'cyrus';
        $MailLocalDelivery{'MailboxSizeLimit'}         = SCR->Read('.etc.imapd_conf.autocreatequota') || 0;
        $MailLocalDelivery{'QuotaLimit'}               = SCR->Read('.etc.imapd_conf.quotawarn') || 0;
        $MailLocalDelivery{'ImapIdleTime'}             = SCR->Read('.etc.imapd_conf.timeout') || 0;
        $MailLocalDelivery{'PopIdleTime'}              = SCR->Read('.etc.imapd_conf.poptimeout') || 0;
        $MailLocalDelivery{'FallBackMailbox'}          = SCR->Read('.etc.imapd_conf.lmtp_luser_relay') || '';
        if(  SCR->Read('.etc.imapd_conf.altnamespace') eq 'yes' )
	{
            $MailLocalDelivery{'AlternateNameSpace'}   = 1; 
        }
	else
	{
            $MailLocalDelivery{'AlternateNameSpace'}   = 0; 
        }
        if(  SCR->Read('.etc.imapd_conf.lmtp_overquota_perm_failure') eq 'yes' )
	{
            $MailLocalDelivery{'HardQuotaLimit'}       = 1; 
        }
	else
	{
            $MailLocalDelivery{'HardQuotaLimit'}       = 0; 
        }
	SCR->Read('.mail.cyrusconf');
	if( SCR->Read('.etc.imapd_conf.tls_cert_file') && SCR->Read('.etc.imapd_conf.tls_cert_file') ne '' &&
	    SCR->Read('.etc.imapd_conf.tls_key_file')  && SCR->Read('.etc.imapd_conf.tls_key_file')  ne '' &&
	    SCR->Read('.etc.imapd_conf.tls_ca_path')   && SCR->Read('.etc.imapd_conf.tls_ca_path')   ne '' &&
	    SCR->Execute('.mail.cyrusconf.serviceExists','imaps') &&
	    SCR->Execute('.mail.cyrusconf.serviceEnabled','imaps') &&
	    SCR->Execute('.mail.cyrusconf.serviceExists','pop3s') &&
	    SCR->Execute('.mail.cyrusconf.serviceEnabled','pop3s') &&
	    SCR->Read(".target.size", '/etc/ssl/certs/YaST-CA.pem') > 0 )
	{
	    $MailLocalDelivery{'Security'} = 1;
	}
    }
    else
    {
        $MailLocalDelivery{'Type'} = 'none';
    }
    return \%MailLocalDelivery;
}


BEGIN { $TYPEINFO{WriteMailLocalDelivery}  =["function", "boolean",["map", "string", "any"], "string"]; }
sub WriteMailLocalDelivery {
    my $self              = shift;
    my $MailLocalDelivery = shift;
    my $AdminPassword     = shift;

    #If nothing to do we don't do antithing
    if(! $MailLocalDelivery->{'Changed'})
    {
         return $self->SetError( summary =>"Nothing to do",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    y2milestone("-- WriteMailLocalDelivery --");
    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }

    # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');
#print STDERR Dumper([$MailLocalDelivery]);   
    if(  $MailLocalDelivery->{'Type'} ne 'none')
    {
        write_attribute($MainCf,'mydestination','$myhostname, localhost.$mydomain, $mydomain, ldap:/etc/postfix/ldapmydestination.cf');
        write_attribute($MainCf,'virtual_alias_maps',   'ldap:/etc/postfix/ldaplocal_recipient_maps.cf, ldap:/etc/postfix/ldapvirtual_alias_maps_member.cf, ldap:/etc/postfix/ldapvirtual_alias_maps.cf');
        write_attribute($MainCf,'virtual_alias_domains','ldap:/etc/postfix/ldapvirtual_alias_domains.cf');
        write_attribute($MainCf,'alias_maps','hash:/etc/aliases, ldap:/etc/postfix/ldapalias_maps_folder.cf, ldap:/etc/postfix/ldapalias_maps.cf');
        check_ldap_configuration('alias_maps_folder',$ldapMap);
        check_ldap_configuration('alias_maps',$ldapMap);
        check_ldap_configuration('virtual_alias_maps_member',$ldapMap);
        check_ldap_configuration('virtual_alias_maps',$ldapMap);
        check_ldap_configuration('virtual_alias_domains',$ldapMap);
    }
    if(  $MailLocalDelivery->{'Type'} eq 'local')
    {
	write_attribute($MainCf,'mailbox_command','');
	write_attribute($MainCf,'mailbox_transport','');
	if($MailLocalDelivery->{'MailboxSizeLimit'} =~ /^\d+$/)
	{
	     write_attribute($MainCf,'mailbox_size_limit',$MailLocalDelivery->{'MailboxSizeLimit'} * 1024 );     
	}
	else
	{
            return $self->SetError( summary => 'Maximum Mailbox Size value may only contain decimal number in byte',
                                      code    => "PARAM_CHECK_FAILED" );
	}
	if($MailLocalDelivery->{'SpoolDirectory'} =~ /\$HOME\/(.*)/)
	{
	   write_attribute($MainCf,'home_mailbox',$1);
	   write_attribute($MainCf,'mail_spool_directory','');
	}
	elsif(-e $MailLocalDelivery->{'SpoolDirectory'})
	{
	   write_attribute($MainCf,'home_mailbox','');
	   write_attribute($MainCf,'mail_spool_directory',$MailLocalDelivery->{'SpoolDirectory'});
	}
	else
	{
            return $self->SetError( summary => 'Bad value for SpoolDirectory. Possible values are:'.
	                                       '"$HOME/<path>" or a path to an existing directory.',
                                      code  => "PARAM_CHECK_FAILED" );
	}
    }
    elsif( $MailLocalDelivery->{'Type'} eq 'procmail')
    {
        write_attribute($MainCf,'home_mailbox','');     
	write_attribute($MainCf,'mail_spool_directory','');
	write_attribute($MainCf,'mailbox_command','/usr/bin/procmail');
	write_attribute($MainCf,'mailbox_transport','');
    }
    elsif( $MailLocalDelivery->{'Type'} eq 'cyrus')
    {
        write_attribute($MainCf,'home_mailbox','');
	write_attribute($MainCf,'mail_spool_directory','');
	write_attribute($MainCf,'mailbox_command','');
	write_attribute($MainCf,'mailbox_transport','lmtp:unix:/var/lib/imap/socket/lmtp'); 
        SCR->Write('.etc.imapd_conf.autocreatequota',$MailLocalDelivery->{'MailboxSizeLimit'});
        SCR->Write('.etc.imapd_conf.quotawarn',$MailLocalDelivery->{'QuotaLimit'});
        SCR->Write('.etc.imapd_conf.timeout',$MailLocalDelivery->{'ImapIdleTime'});
        SCR->Write('.etc.imapd_conf.poptimeout',$MailLocalDelivery->{'PopIdleTime'});
        SCR->Write('.etc.imapd_conf.allowplaintext','yes');
        SCR->Write('.etc.imapd_conf.unixhierarchysep','yes');
        SCR->Write('.etc.imapd_conf.allowplainwithouttls','yes');
        if($MailLocalDelivery->{'FallBackMailbox'} ne ''  )
	{
           SCR->Write('.etc.imapd_conf.lmtp_luser_relay',$MailLocalDelivery->{'FallBackMailbox'});
        }
	else
	{
           SCR->Write('.etc.imapd_conf.lmtp_luser_relay',undef);
        }
        if( $MailLocalDelivery->{'AlternateNameSpace'} )
	{
	    SCR->Write('.etc.imapd_conf.altnamespace','yes');
	}
	else
	{
	    SCR->Write('.etc.imapd_conf.altnamespace','no');
	}
        if( $MailLocalDelivery->{'HardQuotaLimit'} )
	{
	    SCR->Write('.etc.imapd_conf.lmtp_overquota_perm_failure','yes');
        }
	else
	{
	    SCR->Write('.etc.imapd_conf.lmtp_overquota_perm_failure','no');
        }
        if($MailLocalDelivery->{'Security'} )
	{
	  my $size = SCR->Read(".target.size", '/etc/ssl/servercerts/servercert.pem');
          if ($size <= 0)
	  {
              return $self->SetError(summary => "Common server certificate not found.",
                                     code => "PARAM_CHECK_FAILED");
          }
          $size = SCR->Read(".target.size", '/etc/ssl/servercerts/serverkey.pem');
          if ($size <= 0)
	  {
              return $self->SetError(summary => "Common private key not found.",
                                     code => "PARAM_CHECK_FAILED");
          }
          system("setfacl -m g:mail:r /etc/ssl/servercerts/serverkey.pem");
          SCR->Write('.etc.imapd_conf.tls_cert_file','/etc/ssl/servercerts/servercert.pem');
          SCR->Write('.etc.imapd_conf.tls_key_file','/etc/ssl/servercerts/serverkey.pem');
          if(SCR->Read(".target.size", '/etc/ssl/certs/YaST-CA.pem') > 0)
	  {
              #SCR->Write('.etc.imapd_conf.tls_ca_file','/etc/ssl/certs/YaST-CA.pem');
              SCR->Write('.etc.imapd_conf.tls_ca_path','/etc/ssl/certs');
          }
	  SCR->Read('.mail.cyrusconf');
	  if( SCR->Execute('.mail.cyrusconf.serviceExists', 'imaps') &&
	      ! SCR->Execute('.mail.cyrusconf.serviceEnabled', 'imaps') )
	  {
	      SCR->Execute('.mail.cyrusconf.toggleService', 'imaps');
	  }
	  elsif( ! SCR->Execute('.mail.cyrusconf.serviceExists', 'imaps') )
	  {
	      SCR->Execute('.mail.cyrusconf.addService', { sname => "imaps",
							   sarg  => "imapd -s",
							   sport => "imaps" });
	  }
	  if( SCR->Execute('.mail.cyrusconf.serviceExists', 'pop3s') &&
	      ! SCR->Execute('.mail.cyrusconf.serviceEnabled', 'pop3s') )
	  {
	      SCR->Execute('.mail.cyrusconf.toggleService', 'pop3s');
	  }
	  elsif( ! SCR->Execute('.mail.cyrusconf.serviceExists', 'pop3s') )
	  {
	      SCR->Execute('.mail.cyrusconf.addService', { sname => "pop3s",
							   sarg  => "pop3d -s",
							   sport => "pop3s" });
	  }
      }
      else
      {
	  SCR->Read('.mail.cyrusconf');
	  if( SCR->Execute('.mail.cyrusconf.serviceExists', 'imaps') &&
	      SCR->Execute('.mail.cyrusconf.serviceEnabled', 'imaps') )
	  {
	      SCR->Execute('.mail.cyrusconf.toggleService', 'imaps');
	  }
	  if( SCR->Execute('.mail.cyrusconf.serviceExists', 'pop3s') &&
	      SCR->Execute('.mail.cyrusconf.serviceEnabled', 'pop3s') )
	  {
	      SCR->Execute('.mail.cyrusconf.toggleService', 'pop3s');
	  }
      }
      #Create mailbox for root
      my $imap = new Net::IMAP($imaphost, Debug => 0);
      if( $imap )
      {
	  my $ret = $imap->login($imapadm, $AdminPassword);
	  if($$ret{Status} eq "ok")
	  {
	        $ret = $imap->create('user/root'); 
		$ret = $imap->setacl('user/root', 'cyrus', "lrswipkxtea");
		$ret = $imap->setacl('user/root', 'root', "lrswipkxtea");
		$ret = $imap->setacl('user/root', 'anyone', "" );
	  }
          $imap->logout();
      }
    }
    elsif(  $MailLocalDelivery->{'Type'} eq 'none')
    {
        write_attribute($MainCf,'mydestination','');
        write_attribute($MainCf,'virtual_alias_maps','');
        write_attribute($MainCf,'virtual_alias_domains','');
    }
    else
    {
        return $self->SetError( summary => 'Bad value for MailLocalDeliveryType. Possible values are:'.
                                           '"none", "local", "procmail" or "cyrus".',
                                  code  => "PARAM_CHECK_FAILED" );
    }

    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.mail.postfix.main',undef);
    SCR->Write('.etc.imapd_conf',undef);
    SCR->Write('.mail.cyrusconf',undef);
    return 1;
}

BEGIN { $TYPEINFO{ReadFetchingMail}     =["function", "any", "string"]; }
sub ReadFetchingMail {
    my $self            = shift;
    my $AdminPassword   = shift;

    my %FetchingMail = (
                                'Changed'         => YaST::YCP::Boolean(0),
                                'FetchByDialIn'   => 0,
                                'Interface'       => "",
                                'FetchMailSteady' => 1,
                                'FetchingInterval'=> 30,
				'Items'           => []     
				
                       );
#    my $CronTab                 = SCR->Read('.cron','/etc/crontab',\%FetchingMail);
    my $FetchingInterval        = SCR->Read('.sysconfig.fetchmail.FETCHMAIL_POLLING_INTERVAL') || 0; 
    $FetchingMail{'FetchingInterval'} = $FetchingInterval / 60;

    if(! Service->Enabled('fetchmail'))
    {
        $FetchingMail{'FetchMailSteady'} = 0;
    }

    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }

    $FetchingMail{'Items'} = SCR->Read('.mail.fetchmail.accounts');
    
#print STDERR Dumper(%FetchingMail);    

    return \%FetchingMail;
}

BEGIN { $TYPEINFO{WriteFetchingMail}    =["function", "boolean", ["map", "string", "any"], "string"]; }
sub WriteFetchingMail {
    my $self            = shift;
    my $FetchingMail    = shift;
    my $AdminPassword   = shift;

    #If nothing to do we don't do antithing
    if(! $FetchingMail->{'Changed'})
    {
         return $self->SetError( summary =>"Nothing to do",
                                 code    => "PARAM_CHECK_FAILED" );
    }
   
    y2milestone("-- WriteFetchingMail --");
    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }

#print STDERR Dumper([$FetchingMail]);  
    if($FetchingMail->{'Interface'} ne '')
    {
       NetworkInterfaces->Read();
       if($FetchingMail->{'FetchByDialIn'})
       {
          NetworkInterfaces->SetValue($FetchingMail->{'Interface'},'RUN_POLL_TCPIP','yes');
       }
       else
       {
          NetworkInterfaces->SetValue($FetchingMail->{'Interface'},'RUN_POLL_TCPIP','no');
       }
       NetworkInterfaces->Write('ppp|ipp|dsl');
    }
    if($FetchingMail->{'FetchMailSteady'})
    {
       my $FetchingInterval = $FetchingMail->{'FetchingInterval'} * 60;
       SCR->Write('.sysconfig.fetchmail.FETCHMAIL_POLLING_INTERVAL',$FetchingInterval);
       SCR->Write('.sysconfig.fetchmail',undef);
       Service->Enable('fetchmail');
    }
    else
    {
       Service->Disable('fetchmail');
    }

    SCR->Write('.mail.fetchmail.accounts',$FetchingMail->{'Items'});
    SCR->Write('.mail.fetchmail',undef);
    return 1;
}

BEGIN { $TYPEINFO{ReadMailLocalDomains}  =["function", "any", "string"]; }
sub ReadMailLocalDomains {
    my $self             = shift;
    my $AdminPassword    = shift;
    my %MailLocalDomains = (
                                'Changed'         => YaST::YCP::Boolean(0),
                                'Domains'         => []
                           );

    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }
    my $ret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'dns_config_dn'},
                                          "filter"       => '(relativeDomainName=@)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'zoneName', 'suseMailDomainMasquerading', 'suseMailDomainType' ]
                                         });
    if (! defined $ret)
    {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    foreach(@{$ret})
    {
       my $domain = {};
       if( $_->{'zoneName'}->[0] !~ /in-addr.arpa$/i)
       {
         $domain->{'Name'}         = $_->{'zoneName'}->[0];
         $domain->{'Type'}         = $_->{'suseMailDomainType'}->[0]         || 'none';
         $domain->{'Masquerading'} = $_->{'suseMailDomainMasquerading'}->[0] || 'yes';
         push @{$MailLocalDomains{'Domains'}}, $domain;
       }
    }
    return \%MailLocalDomains;
}

BEGIN { $TYPEINFO{WriteMailLocalDomains} =["function", "boolean", ["map", "string", "any"], "string"]; }
sub WriteMailLocalDomains {
    my $self             = shift;
    my $MailLocalDomains = shift;
    my $AdminPassword    = shift;

    my $Domains          = {};

    # We have to work with yast2-dns-server together
    if( -e '/etc/sysconfig/named' )
    {
	my $reload_script = SCR->Read (".sysconfig.named.NAMED_INITIALIZE_SCRIPTS") || "";
	my @reload_scripts = split / /, ((defined $reload_script) ? $reload_script:"");
	my $already_present = scalar (grep (/ldapdump/, @reload_scripts)) > 0;
        if (! $already_present)
        {
            push @reload_scripts, "ldapdump";
	    SCR->Write (".sysconfig.named.NAMED_INITIALIZE_SCRIPTS", $reload_script);
	    SCR->Write (".sysconfig.named", undef);
        }
    }

    #If nothing to do we don't do antithing
    if(! $MailLocalDomains->{'Changed'})
    {
         return $self->SetError( summary =>"Nothing to do",
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    y2milestone("-- WriteMailLocalDomains --");
    # Make LDAP Connection 
    my $ldapMap = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldapMap )
    {
         return undef;
    }
    foreach(@{$MailLocalDomains->{'Domains'}})
    {
      my $name          = $_->{'Name'};
      my $type          = $_->{'Type'} || 'local';
      my $masquerading  = $_->{'Masquerading'} || 'yes';
      if($type !~ /local|virtual|main|none/)
      {
         return $self->SetError( summary =>"Invalid mail local domain type.".
	                                   " Domain: $name; Type $type".
					   "Allowed values are: local|virtual|main.",
                                 code    => "PARAM_CHECK_FAILED" );
      }
      if($masquerading !~ /yes|no/)
      {
         return $self->SetError( summary =>"Invalid mail local domain masquerading value.".
	                                   " Domain: $name; Masquerading: $masquerading".
					   "Allowed values are: yes|no.",
                                 code    => "PARAM_CHECK_FAILED" );
      }
      my $DN = "zoneName=$name,$ldapMap->{'dns_config_dn'}";
      my $retVal = SCR->Read('.ldap.search',{
                                             "base_dn"      => $DN,
                                             "filter"       => '(objectClass=dNSZone)',
                                             "scope"        => 0,
                                             "not_found_ok" => 0
                                            } ); 

      if( defined $retVal && defined $retVal->[0] && defined $retVal->[0]->{'objectClass'}) 
      {
            my $found = 0;
            foreach my $ojc ( @{$retVal->[0]->{'objectClass'}} )
	    {
                if($ojc =~ /^suseMailDomain$/i) {
                    $found = 1;
                    last;
                }
            }
            if($found && $type eq 'none')
	    {
                # delete objectClass

                $Domains->{$DN}->{'objectClass'}                = ['dNSZone'];
                $Domains->{$DN}->{'suseMailDomainType'}         = [];
                $Domains->{$DN}->{'suseMailDomainMasquerading'} = [];

                if( ! SCR->Write('.ldap.modify',{ "dn" => $DN } , $Domains->{$DN}))
		{
                    my $ldapERR = SCR->Read(".ldap.error");
                    return $self->SetError(summary => "LDAP add failed",
                                           code => "SCR_INIT_FAILED",
                                           description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
                }

            }
	    elsif (!$found && $type eq 'none')
	    {
                # do nothing

            }
	    else
	    {
                # modify

                $Domains->{$DN}->{'objectClass'}                = ['dNSZone','suseMailDomain'];
                $Domains->{$DN}->{'zoneName'}                   = $name;
                $Domains->{$DN}->{'suseMailDomainType'}         = $type;
                $Domains->{$DN}->{'suseMailDomainMasquerading'} = $masquerading;
                
                if( ! SCR->Write('.ldap.modify',{ "dn" => $DN } , $Domains->{$DN}))
		{
                    my $ldapERR = SCR->Read(".ldap.error");
                    return $self->SetError(summary => "LDAP modify failed",
                                           code => "SCR_INIT_FAILED",
                                           description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
                }
            }

        }
	else
	{
		# This is a new domain, we create it. 
		# We create all the DNS attributes. `hostname -f` is the NS and MX entry.
		my $serial = POSIX::strftime("%Y%m%d%H%M",localtime);
		my $host   = `hostname -f`; chomp $host;
		my $tmp = { 'Objectclass'                  => [ 'dNSZone','suseMailDomain' ],
		      'zoneName'                     => $name,
		      'suseMailDomainType'           => $type,
		      'suseMailDomainMasquerading'   => $masquerading,
		      'relativeDomainName'	     => '@',
		      'dNSClass'	             => 'IN',
		      'dNSTTL'	                     => '86400',
		      'nSRecord'		     => $host.'.',
		      'mXRecord'		     => '40 '.$host.'.',
		      'sOARecord'                    => $host.'. root.'.$host.'. '.$serial.' 10800 3600 302400 43200'
		 };
		if(! SCR->Write('.ldap.add',{ "dn" => $DN } ,$tmp)){
			my $ldapERR = SCR->Read(".ldap.error");
			return $self->SetError(summary     => "LDAP add failed",
					   code        => "SCR_WRITE_FAILED",
					   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
		}
       }
    }


    # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');
    write_attribute($MainCf,'masquerade_domains','ldap:/etc/postfix/ldapmasquerade_domains.cf');
    write_attribute($MainCf,'masquerade_classes','envelope_sender, header_sender, header_recipient');
    write_attribute($MainCf,'masquerade_exceptions','root');
    write_attribute($MainCf,'mydestination','$myhostname, localhost.$mydomain, $mydomain, ldap:/etc/postfix/ldapmydestination.cf');
    write_attribute($MainCf,'virtual_alias_maps',   'ldap:/etc/postfix/ldaplocal_recipient_maps.cf, ldap:/etc/postfix/ldapvirtual_alias_maps_member.cf, ldap:/etc/postfix/ldapvirtual_alias_maps.cf');
    write_attribute($MainCf,'virtual_alias_domains','ldap:/etc/postfix/ldapvirtual_alias_domains.cf');
    write_attribute($MainCf,'alias_maps','hash:/etc/aliases, ldap:/etc/postfix/ldapalias_maps_folder.cf, ldap:/etc/postfix/ldapalias_maps.cf');
    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.mail.postfix.main',undef);
    check_ldap_configuration('masquerade_domains',$ldapMap);
    check_ldap_configuration('mydestination',$ldapMap);
    check_ldap_configuration('alias_maps_folder',$ldapMap);
    check_ldap_configuration('local_recipient_maps',$ldapMap);
    check_ldap_configuration('alias_maps',$ldapMap);
    check_ldap_configuration('virtual_alias_maps',$ldapMap);
    check_ldap_configuration('virtual_alias_maps_member',$ldapMap);
    check_ldap_configuration('virtual_alias_domains',$ldapMap);
    return 1;
}

=item *

C<$LDAPMap = ReadLDAPDefaults($AdminPassword)>

Reads the LDAP Configuration:
   The LDAP Base
   The LDAP Base for the User Configuration
   The LDAP Base for the Group Configuration
   The LDAP Base for the DNS Configuration
   The LDAP Base for the MAIL Configuration
   The LDAP Template for the MAIL Configuration
If the last there does not exist this will be created.

The result is an hash of following structur:

   $ldapMap = {
         'ldap_server'    => ...,
         'ldap_port'      => ...,
         'bind_pw'        => ...,
         'bind_dn'        => ...,
         'mail_config_dn' => ...,
         'dns_config_dn'  => ...,
         'user_config_dn' => ...,
         'group_config_dn'=> ...,
         
   }

=cut

BEGIN { $TYPEINFO{ReadLDAPDefaults} = ["function", ["map", "string", "any"], "string"]; }
sub ReadLDAPDefaults {
    my $self          = shift;
    my $AdminPassword = shift;

    my $ldapMap       = {};
    my $admin_bind    = {};
    my $ldapret       = undef;
    my $first_use     = 0;

    if(Ldap->Read())
    {
        $ldapMap = Ldap->Export();
        if(defined $ldapMap->{'ldap_server'} && $ldapMap->{'ldap_server'} ne "")
	{
            my $dummy = $ldapMap->{'ldap_server'};
            $ldapMap->{'ldap_server'} = Ldap->GetFirstServer("$dummy");
            $ldapMap->{'ldap_port'} = Ldap->GetFirstPort("$dummy");
        }
	else
	{
            return $self->SetError( summary => "No LDAP Server configured",
                                    code => "HOST_NOT_FOUND");
        }
    }
#print STDERR Dumper([$ldapMap]);
    # Now we try to bind to the LDAP
    if (! SCR->Execute(".ldap", {"hostname" => $ldapMap->{'ldap_server'},
                                 "port"     => $ldapMap->{'ldap_port'}}))
    {
        return $self->SetError(summary => "LDAP init failed",
                               code => "SCR_INIT_FAILED");
    }

    $ldapMap->{'bind_pw'} = $AdminPassword;
    if(! SCR->Execute('.ldap.bind',$ldapMap))
    {
         my $ldapERR = SCR->Read('.ldap.error');
         return $self->SetError(summary     => "LDAP bind failed!",
                                description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                                code        => "LDAP_BIND_FAILED");
    }
    
    # read mail configuration data
    $ldapret = SCR->Read(".ldap.search", {
	"base_dn"      => $ldapMap->{'base_config_dn'},
	"filter"       => '(objectClass=suseMailConfiguration)',
	"scope"        => 2,
	"not_found_ok" => 1,
	"attrs"        => [ 'suseDefaultBase' ]
	});
    if (! defined $ldapret)
    {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret > 0)
    {
        $ldapMap->{'mail_config_dn'} = $ldapret->[0]->{'suseDefaultBase'}->[0];
    }
    else
    {
	# mailconfiguration does not yet exist, so create it
	my $configOBJ;
	my $CONFIG_BASE = "cn=Mailserver,".$ldapMap->{'base_config_dn'};
	my $defaultBase = "ou=Mailserver,".$ldapMap->{'ldap_domain'};
        $ldapMap->{'mail_config_dn'} = $defaultBase;
	$configOBJ->{$CONFIG_BASE}->{'objectClass'} = 'suseMailConfiguration';
	$configOBJ->{$CONFIG_BASE}->{'cn'} = 'Mailserver';
	$configOBJ->{$CONFIG_BASE}->{'suseDefaultBase'} = $defaultBase;
	$configOBJ->{$CONFIG_BASE}->{'suseImapServer'} = "localhost";
	$configOBJ->{$CONFIG_BASE}->{'suseImapAdmin'} = "cyrus";
	$configOBJ->{$CONFIG_BASE}->{'suseImapUseSsl'} = "FALSE";
	$configOBJ->{$CONFIG_BASE}->{'suseImapDefaultQuota'} = 10000;
	$ldapMap->{'bind_pw'} = $AdminPassword;
	if (! SCR->Execute(".ldap.bind", $ldapMap) )
	{
	    my $ldapERR = SCR->Read(".ldap.error");
	    return $self->SetError(summary => "LDAP bind failed",
				   code => "SCR_INIT_FAILED",
				   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
	}
	if( ! SCR->Write('.ldap.add',
			 { "dn" => $CONFIG_BASE },
			 $configOBJ->{$CONFIG_BASE} ) )
	{
            my $ldapERR = SCR->Read(".ldap.error");
            return $self->SetError(summary => "LDAP add failed",
				   code => "SCR_INIT_FAILED",
				   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
	}
        $first_use = 1;
    }


    # check whether ou=Mailserver tree exists
    $ldapret = SCR->Read(".ldap.search", {
	"base_dn"      => $ldapMap->{'ldap_domain'},
	"filter"       => '(&(ou=Mailserver)(objectClass=organizationalUnit))',
	"scope"        => 2,
	"not_found_ok" => 1,
	"attrs"        => [ 'ou' ]
	});
    if (! defined $ldapret)
    {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if( @$ldapret == 0)
    {
	# create it
	my $configOBJ;
	my $uBase = "ou=Mailserver,".$ldapMap->{'ldap_domain'};
	$configOBJ->{$uBase}->{'objectClass'} = 'organizationalUnit';
	$configOBJ->{$uBase}->{'ou'} = 'Mailserver';
	$ldapMap->{'bind_pw'} = $AdminPassword;
	if (! SCR->Execute(".ldap.bind", $ldapMap) )
	{
	    my $ldapERR = SCR->Read(".ldap.error");
	    return $self->SetError(summary => "LDAP bind failed",
				   code => "SCR_INIT_FAILED",
				   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
	}
	if( ! SCR->Write('.ldap.add',
			 { "dn" => $uBase },
			 $configOBJ->{$uBase} ) )
	{
            my $ldapERR = SCR->Read(".ldap.error");
            return $self->SetError(summary => "LDAP add failed",
				   code => "SCR_INIT_FAILED",
				   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
	}
    }


    # check whether mail plugin is already in the pluginlist
    $ldapret = SCR->Read(".ldap.search", {
	"base_dn"      => $ldapMap->{'base_config_dn'},
	"filter"       => '(objectClass=suseUserTemplate)',
	"scope"        => 2,
	"not_found_ok" => 1
	});
    if (! defined $ldapret)
    {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if( @$ldapret > 0)
    {
	# 
	my $foundplugin = 0;
	if( defined $ldapret->[0]->{'susePlugin'} )
	{
	    foreach my $sp ( @{$ldapret->[0]->{'susePlugin'}} )
	    {
		$foundplugin = 1 if lc($sp) eq "userspluginmail";
	    }
	    if( ! $foundplugin )
	    {
		$ldapMap->{'bind_pw'} = $AdminPassword;
		if (! SCR->Execute(".ldap.bind", $ldapMap) )
		{
		    my $ldapERR = SCR->Read(".ldap.error");
		    return $self->SetError(summary => "LDAP bind failed",
					   code => "SCR_INIT_FAILED",
					   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
		}
		my $dn = "cn=userTemplate,".$ldapMap->{'base_config_dn'};
		my $pluginlist = $ldapret->[0]->{'susePlugin'};
		push @$pluginlist, 'UsersPluginMail';
		if( ! SCR->Write('.ldap.modify',
				 { "dn" => $dn },
				 { 'susePlugin' => $pluginlist } ) )
		{
		    my $ldapERR = SCR->Read(".ldap.error");
		    return $self->SetError(summary => "LDAP modify failed",
					   code => "SCR_INIT_FAILED",
					   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
		}
	    }
	}
    }
    else
    {
        return $self->SetError(summary => "Plugintemplate not found",
                               description => "The entry cn=userTemplate,$ldapMap->{'base_config_dn'} is missing in the LDAP server.",
                               code => "MAIL_PLUGIN_TEMPLATE_NOT_FOUND");
    }
    
    # now we search user base
    $ldapret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'base_config_dn'},
                                          "filter"       => '(objectClass=suseUserConfiguration)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'suseDefaultBase' ]
                                         });
    if (! defined $ldapret)
    {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret > 0)
    {
        $ldapMap->{'user_config_dn'} = $ldapret->[0]->{'suseDefaultBase'}->[0];
    }
    # now we search group base
    $ldapret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'base_config_dn'},
                                          "filter"       => '(objectClass=suseGroupConfiguration)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'suseDefaultBase' ]
                                         });
    if (! defined $ldapret)
    {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret > 0)
    {
        $ldapMap->{'group_config_dn'} = $ldapret->[0]->{'suseDefaultBase'}->[0];
    }
    # now we search DNS base
    $ldapret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'base_config_dn'},
                                          "filter"       => '(objectClass=suseDNSConfiguration)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'suseDefaultBase' ]
                                         });
    if (! defined $ldapret)
    {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret > 0) {
        $ldapMap->{'dns_config_dn'} = $ldapret->[0]->{'suseDefaultBase'}->[0];
    }
    else
    {
       # We create the DNS config if there is no any.
       my $DN  = 'ou=DNS,'.$ldapMap->{'ldap_domain'};
       my $tmp = { objectClass     => [ "top" , "suseDnsConfiguration" ],
                   cn              => 'defaultDNS',
		   suseDefaultBase => $DN
                 };
       if( ! SCR->Write('.ldap.add', { dn => 'cn=defaultDNS,'.$ldapMap->{'base_config_dn'} }, $tmp ) )
       {
            my $ldapERR = SCR->Read(".ldap.error");
            return $self->SetError(summary => "LDAP add failed",
				   code => "SCR_INIT_FAILED",
				   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
       $ldapMap->{'dns_config_dn'} = $DN;
    }   
    $ldapret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'dns_config_dn'},
                                          "filter"       => '(ou=DNS)',
                                          "scope"        => 0,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'ou' ]
                                         });
    if (! defined $ldapret)
    {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret != 1)
    {
       # There is no ou=DNS object, we create it.
       my $tmp = { objectClass => [ 'top' , 'organizationalUnit' ],
                   ou          => 'DNS'     
               };
       if( ! SCR->Write('.ldap.add', { dn => $ldapMap->{'dns_config_dn'}}, $tmp ) ) 
       {
            my $ldapERR = SCR->Read(".ldap.error");
            return $self->SetError(summary => "LDAP add failed",
				   code => "SCR_INIT_FAILED",
				   description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }
    return $ldapMap;
}
##
 # Create a textual summary and a list of unconfigured cards
 # @return summary of the current configuration
 #
BEGIN { $TYPEINFO{Summary} = ["function", [ "list", "string" ] ]; }
sub Summary {
    # TODO FIXME: your code here...
    # Configuration summary text for autoyast
    return (
        _("Configuration summary ...")
    );
}

##
 # Create an overview table with all configured cards
 # @return table items
 #
BEGIN { $TYPEINFO{Overview} = ["function", [ "list", "string" ] ]; }
sub Overview {
    # TODO FIXME: your code here...
    return ();
}

##
 # Return packages needed to be installed and removed during
 # Autoinstallation to insure module has all needed software
 # installed.
 # @return hash with 2 lists.
 #
BEGIN { $TYPEINFO{AutoPackages} = ["function", ["map", "string", ["list", "string"]]]; }
sub AutoPackages {
    # TODO FIXME: your code here...
    my %ret = (
        "install" => (),
        "remove" => (),
    );
    return \%ret;
}

=item *

C<boolean = ResetMailServer($AdminPassword)>

Funktion to reset the mail server configuration:
Needed Parameters are:
   $AdminPassword the Adminstrator Psssword

   Sets Maximum Mail Size to 10MB
   Sets Sending Mail Type to DNS
   Sets Mail Server Basic Protection to off
   Sets Mail Local Delivery Type to local
   Sets up the needed LDAP lookup tables
   Sets the postfix variables:
      mydestination
      masquerade_classes
      masquerade_exceptions

=cut
BEGIN { $TYPEINFO{ResetMailServer} = ["function",  "boolean" ,"string"]; }
sub ResetMailServer {
    my $self            = shift;
    my $AdminPassword   = shift;
    my $ldapMap         = $self->ReadLDAPDefaults($AdminPassword);
    my $check_postfix = 'if [ -z "$(id postfix | grep -E \'groups=.*mail\')" ]; then
usermod -G mail postfix
fi';

    # Now we setup postfix basicaly
    SCR->Write(".sysconfig.mail.MAIL_CREATE_CONFIG","yes");
    SCR->Write(".sysconfig.mail",undef);
    SCR->Execute(".target.bash", "SuSEconfig -module postfix");
    SCR->Write(".sysconfig.mail.MAIL_CREATE_CONFIG","no");
    SCR->Write(".sysconfig.mail",undef);

    #Put user postfix into the group mail
    system($check_postfix);

    #Setup Global Settings;
    my $TLS = "use";
    my $size = SCR->Read(".target.size", '/etc/ssl/servercerts/servercert.pem');
    if ($size <= 0)
    {
	$TLS = "none";	
    }
    my $TMP = $self->ReadGlobalSettings($AdminPassword);
       $TMP->{'Changed'}               = 1;
       $TMP->{'MaximumMailSize'}       = '10240000';
       $TMP->{'Interfaces'}            = 'all';
       $TMP->{'SendingMail'}->{'Type'} = 'DNS';
       $TMP->{'SendingMail'}->{'TLS'}  = 'NONE';
       $self->WriteGlobalSettings($TMP,$AdminPassword); 
    #Setup Mail Server Preventions
       $TMP = $self->ReadMailPrevention($AdminPassword);
       $TMP->{'Changed'}               = 1;
       $TMP->{'BasicProtection'}       = 'medium';
       $TMP->{'VirusScanning'}         = 1;
       $TMP->{'VSCount'}               = 2;
       $TMP->{'SpamLearning'}          = 0;
       $self->WriteMailPrevention($TMP,$AdminPassword); 
    #Setup Mail Server Relaying

       $TMP = $self->ReadMailRelaying($AdminPassword);
       $TMP->{'Changed'}               = 1;
       $TMP->{'RequireSASL'}           = '0';
       $TMP->{'SMTPDTLSMode'}          = $TLS;
       $self->WriteMailRelaying($TMP,$AdminPassword); 
    #Setup Local Delivery
       $TMP = $self->ReadMailLocalDelivery($AdminPassword);
       $TMP->{'Changed'}               = 1;
       $TMP->{'Type'}                  = 'local';
       $TMP->{'MailboxSizeLimit'}      = 0;
       $TMP->{'SpoolDirectory'}        = '/var/spool/mail';
       $self->WriteMailLocalDelivery($TMP,$AdminPassword); 

    #Read the main configuration
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    # Setup the tlsmanager service if necessary
    if( ! SCR->Read('.mail.postfix.mastercf') )
    {
       return $self->SetError( summary =>"Couln't open master.cf",
                               code    => "PARAM_CHECK_FAILED" );
    }
    my $tlsmgr = SCR->Execute('.mail.postfix.mastercf.findService',
                   { 'service' => 'tlsmgr',
                     'command' => 'tlsmgr' });
    if( $TLS eq "use" )
    {
      write_attribute($MainCf,'smtpd_tls_cert_file','/etc/ssl/servercerts/servercert.pem');
      write_attribute($MainCf,'smtpd_tls_key_file','/etc/ssl/servercerts/serverkey.pem');
      if(SCR->Read(".target.size", '/etc/ssl/certs/YaST-CA.pem') > 0)
      {
          #write_attribute($MainCf,'smtpd_tls_CAfile','/etc/ssl/certs/YaST-CA.pem');
          write_attribute($MainCf,'smtpd_tls_CApath','/etc/ssl/certs');
      }
      if(! defined $tlsmgr )
      {
           SCR->Execute('.mail.postfix.mastercf.addService',
           { 'service' => 'tlsmgr',
             'type'    => 'unix',
             'private' => '-',
             'unpriv'  => '-',
             'chroot'  => 'n',
             'wakeup'  => '1000?',
             'maxproc' => '1',
             'command' => 'tlsmgr' });
      }
    }
    else
    {
      if( defined $tlsmgr )
      {
         SCR->Execute('.mail.postfix.mastercf.deleteService', {'service' => 'tlsmgr','command' => 'tlsmgr'});
      }
    }
    #Setup the ldap tables;
    # Transport
    check_ldap_configuration('transport_maps',$ldapMap);
    write_attribute($MainCf,'transport_maps','ldap:/etc/postfix/ldaptransport_maps.cf');
    # smtp_tls_per_site
    check_ldap_configuration('smtp_tls_per_site',$ldapMap);
    write_attribute($MainCf,'smtp_tls_per_site','ldap:/etc/postfix/ldapsmtp_tls_per_site.cf');
    #
    write_attribute($MainCf,'masquerade_domains','ldap:/etc/postfix/ldapmasquerade_domains.cf');
    write_attribute($MainCf,'masquerade_classes','envelope_sender, header_sender, header_recipient');
    write_attribute($MainCf,'masquerade_exceptions','root');
    write_attribute($MainCf,'content_filter','');
    write_attribute($MainCf,'mydestination','$myhostname, localhost.$mydomain, $mydomain, ldap:/etc/postfix/ldapmydestination.cf');
    write_attribute($MainCf,'virtual_alias_maps',   'ldap:/etc/postfix/ldaplocal_recipient_maps.cf, ldap:/etc/postfix/ldapvirtual_alias_maps_member.cf, ldap:/etc/postfix/ldapvirtual_alias_maps.cf');
    write_attribute($MainCf,'virtual_alias_domains','ldap:/etc/postfix/ldapvirtual_alias_domains.cf');
    write_attribute($MainCf,'alias_maps','hash:/etc/aliases, ldap:/etc/postfix/ldapalias_maps_folder.cf, ldap:/etc/postfix/ldapalias_maps.cf');
    check_ldap_configuration('transport_maps',$ldapMap);
    check_ldap_configuration('smtp_tls_per_site',$ldapMap);
    check_ldap_configuration('masquerade_domains',$ldapMap);
    check_ldap_configuration('mydestination',$ldapMap);
    check_ldap_configuration('local_recipient_maps',$ldapMap);
    check_ldap_configuration('alias_maps_folder',$ldapMap);
    check_ldap_configuration('alias_maps',$ldapMap);
    check_ldap_configuration('virtual_alias_maps',$ldapMap);
    check_ldap_configuration('virtual_alias_maps_member',$ldapMap);
    check_ldap_configuration('virtual_alias_domains',$ldapMap);
    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.mail.postfix.main',undef);
    SCR->Write('.mail.postfix.mastercf',undef);
    SCR->Execute(".target.bash", "touch /var/adm/yast2-mail-server-used");

    return 1;
}

# some helper funktions
sub read_attribute {
    my $config    = shift;
    my $attribute = shift;

    foreach(@{$config})
    {
        if($_->{"key"} eq $attribute)
	{
                return $_->{"value"};
        }
    }
    return '';
}


sub activate_virus_scanner {
   my $VSCount = shift || 5;
   use File::Copy;
   
   my $cconf = "/etc/clamd.conf";
   my $clamsock = '/var/lib/clamav/clamd-socket';
   my @CONF = ();
   
   if( ! open(IN,$aconf) )
   {
       return "Error: $!";
   }
   my @ACONF = <IN>;
   close(IN);
   
   my $isclam       = 0;
   my $ismax        = 0;
   my $ismyhostname = 0;
   my $myhostname   = `hostname -f`; chomp $myhostname;
   my $mydomain     = `hostname -d`; chomp $mydomain;
   foreach my $l ( @ACONF )
   {
	if ( $l =~ s/^\$max_servers = .*;/\$max_servers = $VSCount;/ )
	{
	   next if $ismax;
	   $ismax = 1;
	}
	if ( $l =~ s/^\$myhostname = .*;/\$myhostname = '$myhostname';/ )
	{
	   next if $ismyhostname;
	   $ismyhostname = 1;
	}
	if ( $l =~ s/^\$mydomain = .*;/\$mydomain = '$mydomain';/ )
	{
	   push @CONF, $l;
	   next ;
	}
   	$l =~ s/(.*)/# $1/ if $l =~ /bypass_virus_checks_acl.*=.*qw\( \./;
   	if( $isclam || $l =~ /Clam Antivirus-clamd/ )
	{
   	    $isclam = 1 if $l =~ /Clam Antivirus-clamd/;
   	    $isclam = 0 if $l =~ /Infected Archive.*FOUND/;
   	    $l =~ s/^#\s*//;
   	    if( $l =~ /ask_daemon/ )
	    {
   		$l =~ s/^(.*\").*(\".*)$/$1$clamsock$2/;
            }
   	}
	push @CONF, $l;
   }
   pop @CONF;
   if( !$ismax )
   {
       push @CONF, '$max_servers = '.$VSCount.";\n";
   }
   if( !$ismyhostname )
   {
       push @CONF, '$myhostname = '."'$myhostname';\n";
   }
   if( ! open(OUT,">$aconf.new") )
   {
       return "Error: $!";
   }
   push @CONF, '1;';
   print OUT @CONF;
   close(OUT);
   
   if( ! open(IN,$cconf) )
   {
       return "Error: $!";
   }
   my @CCONF = <IN>;
   close(IN);
   @CONF = ();
   
   foreach my $l ( @CCONF )
   {
   	$l = "LocalSocket $clamsock\n" if $l =~ /LocalSocket/;
   	$l =~ s/(.*)/#$1/ if $l =~ /^TCPSocket/;
   	$l =~ s/(.*)/#$1/ if $l =~ /^TCPAddr/;
	push @CONF, $l;
   }
   if( ! open(OUT,">$cconf.new") )
   {
       return "Error: $!";
   }
   print OUT @CONF;
   close(OUT);
   copy($aconf,"$aconf.bak");
   copy($cconf,"$cconf.bak");
   move("$aconf.new",$aconf);
   move("$cconf.new",$cconf);
   Service->Enable('amavis');
   Service->Enable('clamd');
   Service->Start('amavis');
   Service->Start('clamd');
   return "";
}

sub write_attribute {
    my $config    = shift;
    my $attribute = shift;
    my $value     = shift;
    my $comment   = shift;

    my $unset = 1;

    foreach(@{$config})
    {
        if($_->{"key"} eq $attribute)
	{
            $_->{"value"} = $value;
            $unset = 0; 
            last;
        }
    }
    if($unset)
    {
        push (@{$config}, { "comment" => $comment,
                                "key" => $attribute,
                              "value" => $value }
                  );
    }
    return 1;
}

# Internal helper Funktion to check if a needed ldap table is correctly defined
# in the main.cf. If not so the neccesary entries will be created.
sub check_ldap_configuration {
    my $config      = shift;
    my $ldapMap    = shift;

    my $changes   = 0;
    my %query_filter     = (
                        'transport_maps'      => '(&(objectClass=suseMailTransport)(suseMailTransportDestination=%s))',
                        'smtp_tls_per_site'   => '(&(objectClass=suseMailTransport)(suseMailTransportDestination=%s))',
                        'access'              => '(&(objectClass=suseMailAccess)(suseMailClient=%s))',
                        'local_recipient_maps'=> '(&(objectClass=suseMailRecipient)(|(suseMailAcceptAddress=%s)(uid=%s)))',
                        'alias_maps'          => '(&(objectClass=suseMailRecipient)(|(uid=%s)(cn=%s)))',
                        'alias_maps_folder'   => '(&(objectClass=suseMailRecipient)(cn=%s)(suseDeliveryToFolder=yes))',
                        'mynetworks'          => '(&(objectClass=suseMailMyNetworks)(suseMailClient=%s))',
                        'masquerade_domains'  => '(&(objectClass=suseMailDomain)(zoneName=%s)(suseMailDomainMasquerading=yes))',
                        'mydestination'       => '(&(objectClass=suseMailDomain)(zoneName=%s)(relativeDomainName=@)(!(suseMailDomainType=virtual)))',
                        'virtual_alias_maps_member'   => '(&(objectClass=suseMailRecipient)(suseMailAcceptAddress=%s)(suseDeliveryToMember=yes))',
			'virtual_alias_maps'  => '(&(objectclass=suseMailRecipient)(suseMailAcceptAddress=%s))',
                        'virtual_alias_domains'  => '(&(objectClass=suseMailDomain)(zoneName=%s)(relativeDomainName=@)(suseMailDomainType=virtual))',
                        'canonical_maps'      => '(&(objectClass=suseCanonicalTable)(tableKey=%s)(valueType=both))',
                        'recipient_canonical_maps' => '(&(objectClass=suseCanonicalTable)(tableKey=%s)(valueType=recipient))',
                        'sender_canonical_maps' => '(&(objectClass=suseCanonicalTable)(tableKey=%s)(valueType=sender))'
                       );
    my %result_attribute = (
                        'transport_maps'      => 'suseMailTransportNexthop',
                        'smtp_tls_per_site'   => 'suseTLSPerSiteMode',
                        'access'              => 'suseMailAction',
                        'local_recipient_maps'=> 'uid',
                        'alias_maps'          => 'suseMailForwardAddress',
                        'alias_maps_folder'   => 'suseMailCommand',
                        'mynetworks'          => 'suseMailClient',
                        'masquerade_domains'  => 'zoneName',
                        'mydestination'       => 'zoneName',
                        'virtual_alias_maps_member'   => 'uid',
                        'virtual_alias_maps'  => 'cn',
                        'virtual_alias_domains'  => 'zoneName',
                        'canonical_maps'      => 'tableValue',
                        'recipient_canonical_maps' => 'tableValue',
                        'sender_canonical_maps'    => 'tableValue'
                       );
    my %scope            = (
                        'transport_maps'      => 'one',
                        'smtp_tls_per_site'   => 'one',
                        'access'              => 'one',
                        'local_recipient_maps'=> 'one',
                        'alias_maps'          => 'one',
                        'alias_maps_folder'   => 'one',
                        'mynetworks'          => 'one',
                        'masquerade_domains'  => 'sub',
                        'mydestination'       => 'sub',
                        'virtual_alias_maps_member'   => 'one',
                        'virtual_alias_maps'  => 'one',
                        'virtual_alias_domains'  => 'sub',
                        'canonical_maps'      => 'one',
                        'recipient_canonical_maps' => 'one',
                        'sender_canonical_maps'    => 'one'
                       );
    my %base            = (
                        'transport_maps'      => $ldapMap->{'mail_config_dn'},
                        'smtp_tls_per_site'   => $ldapMap->{'mail_config_dn'},
                        'access'              => $ldapMap->{'mail_config_dn'},
                        'local_recipient_maps'=> $ldapMap->{'user_config_dn'},
                        'alias_maps'          => $ldapMap->{'ldap_domain'},
                        'alias_maps_folder'   => $ldapMap->{'group_config_dn'},
                        'mynetworks'          => $ldapMap->{'mail_config_dn'},
                        'masquerade_domains'  => $ldapMap->{'dns_config_dn'},
                        'mydestination'       => $ldapMap->{'dns_config_dn'},
                        'virtual_alias_maps_member'   => $ldapMap->{'group_config_dn'},
                        'virtual_alias_maps'  => $ldapMap->{'group_config_dn'},
                        'virtual_alias_domains'  => $ldapMap->{'dns_config_dn'},
                        'canonical_maps'      => $ldapMap->{'mail_config_dn'},
                        'recipient_canonical_maps' => $ldapMap->{'mail_config_dn'},
                        'sender_canonical_maps'    => $ldapMap->{'mail_config_dn'}
                       );
    my %special_result_attribute = (
                        'virtual_alias_maps_member'   => 'member',
		       );



    #First we read the whool main.cf configuration
    my $LDAPCF    = SCR->Read('.mail.ldaptable',$config);

    #Now we are looking for if all the needed ldap entries are done
    if(!$LDAPCF->{'server_host'} || $LDAPCF->{'server_host'} ne $ldapMap->{'ldap_server'})
    {
	 $changes = 1;
    }
    if(! $LDAPCF->{'server_port'} || $LDAPCF->{'server_port'} ne $ldapMap->{'ldap_port'})
    {
	 $changes = 1;
    }
    if(! $LDAPCF->{'bind'}  || $LDAPCF->{'bind'} ne 'no')
    {
	 $changes = 1;
    }
    if(! $LDAPCF->{'timeout'} || $LDAPCF->{'timeout'} !~ /^\d+$/)
    {
	 $changes = 1;
    }
    if(! $LDAPCF->{'search_base'} || $LDAPCF->{'search_base'} ne $base{$config})
    {
	 $changes = 1;
    }
    if(! $LDAPCF->{'query_filter'} || $LDAPCF->{'query_filter'} ne $query_filter{$config})
    {
	 $changes = 1;
    }
    if(! $LDAPCF->{'result_attribute'} || $LDAPCF->{'result_attribute'} ne $result_attribute{$config})
    {
	 $changes = 1;
    }
    if(! $LDAPCF->{'scope'} || $LDAPCF->{'scope'} ne $scope{$config})
    {
	 $changes = 1;
    }

    # If we had made changes we have to save it
    if( $changes )
    {
        $LDAPCF->{'server_host'}      = $ldapMap->{'ldap_server'};
        $LDAPCF->{'server_port'}      = $ldapMap->{'ldap_port'};
        $LDAPCF->{'bind'}             = 'no';
        $LDAPCF->{'timeout'}          = '20';
        $LDAPCF->{'search_base'}      = $base{$config}; 
        $LDAPCF->{'query_filter'}     = $query_filter{$config}; 
        $LDAPCF->{'result_attribute'} = $result_attribute{$config}; 
	if(defined $special_result_attribute{$config})
	{
		$LDAPCF->{'special_result_attribute'} = $special_result_attribute{$config};
	}
        $LDAPCF->{'scope'}            = $scope{$config}; 

	SCR->Write('.mail.ldaptable',[$config,$LDAPCF]);
    }

    return $changes;
}

1;

# EOF
