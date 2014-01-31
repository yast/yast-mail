# encoding: utf-8

# File:	include/mail/helps.ycp
# Package:	Configuration of mail-server
# Summary:	Help texts of all the dialogs
# Authors:	Peter Varkoly <varkoly@suse.de>
#
# $Id: helps.ycp 20143 2004-11-03 12:05:30Z varkoly $
module Yast
  module MailMailServerHelpsInclude
    def initialize_mail_mail_server_helps(include_target)
      textdomain "mail"

      # All helps are here
      @HELPS = {
        # AuthorizingDialog dialog help 1/2
        "AuthorizingDialog" => _(
          "<p><b><big>Administrator Authorization</big></b><br>\n" +
            "To use the YaST mail server component, your system must use LDAP\n" +
            "as a repository for the user and group accounts and for the DNS services.<br>\n" +
            "Some of the mail server settings will be stored in the LDAP repository, too.<br></p>\n"
        ),
        # Setup dialog help 1/1
        "setup"             => _(
          "<p><b><big>Set Up Mail Server Configuration</big></b><br>\n</p>\n"
        ),
        # Read dialog help 1/2
        "read"              => _(
          "<p><b><big>Initializing Mail Server Configuration</big></b><br>\nPlease wait...<br></p>\n"
        ) +
          # Read dialog help 2/2
          _(
            "<p><b><big>Aborting Initialization:</big></b><br>\nSafely abort the configuration utility by pressing <b>Abort</b> now.</p>\n"
          ),
        # Write dialog help 1/2
        "write"             => _(
          "<p><b><big>Saving Mail Server Configuration</big></b><br>\nPlease wait...<br></p>\n"
        ) +
          # Write dialog help 2/2
          _(
            "<p><b><big>Aborting Saving:</big></b><br>\n" +
              "Abort the save procedure by pressing <b>Abort</b>.\n" +
              "An additional dialog informs whether it is safe to do so.\n" +
              "</p>\n"
          ),
        # GlobalSettings dialog help 1/3
        "GlobalSettings"    => _(
          "<p><b><big>Server Identification:</big></b><br>\n" +
            "This is the SMTP server's greeting banner.</b>.\n" +
            "<br></p>\n"
        ) +
          # GlobalSettings dialog help 2/3
          _(
            "<p><b><big>Mail Size:</big></b><br>\n" +
              "This parameter limits the total size in bytes of a mail (sending and getting),\n" +
              "including envelope information.\n" +
              "</p>"
          ) +
          # GlobalSettings dialog help 3/3
          _(
            "<p><b><big>Outgoing Mails:</big></b><br>\n" +
              "Set the transport type for outgoing mails.\n" +
              "</p>\n"
          ),
        # MailTransports dialog help 1/2
        "MailTransports"    => _(
          "<p><b><big>Manage Mail Routing</big></b><br>\n" +
            "Add or modify mail transport routes.\n" +
            "<br></p>\n"
        ) +
          # MailTransports dialog help 2/2
          _(
            "<p><b><big>Defined Mail Transport Routes</big></b><br>\n" +
              "This is the list of the defined mail transports.\n" +
              "</p>\n"
          ),
        # MailPrevention dialog help 1/3
        "MailPrevention"    => _(
          "<p><b><big>SPAM Prevention</big></b><br>\n" +
            "Postfix offers a variety of parameters that limit the delivery of unsolicited commercial e-mail (UCE).\n" +
            "In this dialog, configure this settings.  For example, set access lists or RBL\n" +
            "(real-time blackhole list) name servers. \n" +
            "<br></p>\n"
        ) +
          # MailPrevention dialog help 2/3
          _(
            "<p><b><big>Start Virus Scanner AMAVIS:</big></b><br>\n" +
              "If you start the virus scanner AMAVIS, your emails will be scanned for viruses and and for spam.\n" +
              "The virus scanner engine <b>Clamavd</b> and the spam finder <b>SpamAssassin</b> will be installed \n" +
              "and configured as well. You can also install other (commercial) virus scanner engines.\n" +
              "</p>\n"
          ) +
          # MailPrevention dialog help 3/3
          _(
            "<p><b><big>Configure Spam Learning Extension:</big></b><br>\n" +
              "The spam learning extension can only be configured if the local delivery method is <b>dovecot imap</b>.\n" +
              "In this case the shared folders <b>NewSpam</b> and <b>NoSpam</b> will be created. Spam email \n" +
              "which was not detected by <b>SpamAssassin</b> should be put into the folder <b>NewSpam</b>.\n" +
              "If you want your spam finder to be most effective you should also put non-spam email into\n" +
              "the folder <b>NoSpam</b>. The emails in this folder cannot be read by anyone.\n" +
              "</p>\n"
          ),
        # MailRelaying dialog help 1/2
        "MailRelaying"      => _(
          "<p><b><big>Trusted Local Networks:</big></b><br>\n" +
            "Clients from these networks can use your mail server for mail relaying.\n" +
            "(Sending non-local mails)\n" +
            "<br></p>\n"
        ) +
          # MailRelaying dialog help 2/2
          _(
            "<p><b><big>Require SASL Authentication:</big></b><br>\n" +
              "If set to true, clients must authenticate to use\n" +
              "the mail server for mail relaying. \n" +
              "<br></p>\n"
          ),
        # MailLocalDelivery dialog help 1/2
        "MailLocalDelivery" => _(
          "<p><b><big>Local Delivery Type</big></b><br>\n" +
            "In this frame, choose the local mail delivery method. \n" +
            "For clients to be able to connect to your mail server via the POP or IMAP\n" +
            "protocol, choose <b>Cyrus IMAP</p>. \n" +
            "<br></p>\n"
        ) +
          # MailLocalDelivery dialog help 2/2
          _(
            "<p>Depending on the local delivery method, you have\n" +
              "different possibilities of settings.\n" +
              "</p>\n"
          ),
        # FetchingMail dialog help 1/2
        "FetchingMail"      => _(
          "<p><b><big>Mail Fetching Scheduler</big></b><br>\n" +
            "If you have mail boxes on an Internet provider, you can fetch this regularly\n" +
            "at defined time intervals and by connecting to the Internet.\n" +
            "<br></p>\n"
        ) +
          # FetchingMail dialog help 2/2
          _(
            "<p>Note: If you have not defined any local delivery type, you cannot\n" +
              "define mail fetching jobs.\n" +
              "</p>\n"
          ),
        # MailLocalDomains dialog help 1/3
        "MailLocalDomains"  => _(
          "<p><b><big>Mail Server Domains</big></b><br>\n" +
            "Here, define the domains for which your mail server considers itself \n" +
            "the final destination.\n" +
            "<br></p>\n"
        ) +
          # MailLocalDomains dialog help 2/3
          _(
            "<p>Note: You can create and set up the domains with the YaST \n" +
              "DNS server module. In the current module, you only can set the properties\n" +
              "concerning the mail server.\n" +
              "</p>\n"
          ) +
          # MailLocalDomains dialog help 3/3
          _(
            "<p><b><big>Type:</big></b><br>\n" +
              "You can define virtual and local domains. In virtual domains, only users\n" +
              "assigned an email address in the domain can receive emails.\n" +
              "In local domains, all users can get emails. Assign virtual email \n" +
              "addresses in the YaST user module.\n" +
              "</p>\n"
          )
      } 

      # EOF
    end
  end
end
