# encoding: utf-8

# File:
#   include/mail/helps.ycp
#
# Package:
#   Configuration of mail
#
# Summary:
#   Help texts of all the dialogs.
#
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
#
# The help texts.
#
module Yast
  module MailHelpsInclude
    def initialize_mail_helps(include_target)
      textdomain "mail"
    end

    # Help for the ReadDialog () dialog.
    # @return The help text.
    def ReadDialogHelp
      # TODO FIXME: Modify it to your needs!
      # For translators: mail read dialog help, part 1 of 2
      _(
        "<P><B><BIG>Initializing mail</BIG></B><BR>\n" +
          "Please wait...\n" +
          "<BR></P>\n"
      ) +
        # For translators: mail read dialog help, part 2 of 2
        _(
          "<P><B><BIG>Aborting the initialization:</BIG></B><BR>\n" +
            "Safely abort the configuration utility by pressing <B>Abort</B>\n" +
            "now.\n" +
            "</P>\n"
        )
    end

    # Help for the WriteDialog () dialog.
    # @return The help text.
    def WriteDialogHelp
      # TODO FIXME: Modify it to your needs!
      # For translators: mail write dialog help, part 1 of 2
      _(
        "<P><B><BIG>Saving mail configuration</BIG></B><BR>\n" +
          "Please wait...\n" +
          "<BR></P>\n"
      ) +
        # For translators: mail write dialog help, part 2 of 2
        _(
          "<P><B><BIG>Aborting saving:</BIG></B><BR>\n" +
            "Abort saving by pressing <B>Abort</B>.\n" +
            "An additional dialog will inform you whether it is safe to do so.\n" +
            "</P>\n"
        )
    end

    # @return Help for MTA selection dialog
    def MtaSelectionDialogHelp
      # Translators: mailer (MTA) selection dialog help, part 1 of 1
      # do not translate MTA
      _("<p>Select the mail system (Mail Transfer Agent, MTA)\nto install.</p>")
    end

    # @return Help for Connection type dialog
    def ConnectionTypeDialogHelp
      # Translators: connection type dialog help, part 1 of 2
      s = _(
        "\n" +
          "<p>How are you connected to the Internet? With a dial-up connection,\n" +
          "mails will not be sent immediately but rather after invoking\n" +
          "<b>sendmail&nbsp;-q</b>.</p>\n"
      ) +
        _(
          "<p>If choosing <b>No Connection</b>, the mail server will be started.\nHowever, only local mail transport is possible. The MTA listens to the localhost.</p>\n"
        )
      s
    end

    # @return Help for Detailed address rewriting dialog
    def MasqueradingDialogHelp
      # Translators: masquerading dialog help, part 1 of 1
      _(
        "\n<p>Specify the rewriting of the sender's address here for each user.</p>\n"
      )
    end

    # @return Help for Detailed address rewriting dialog
    def AuthenticationDialogHelp
      # Translators: authentication dialog help 1/4
      _(
        "\n" +
          "<p>Some servers require authentication for sending mails. Here you can\n" +
          "enter information for this option. If you do not want to use authentication,\n" +
          "simply leave these fields empty.</p>\n"
      ) +
        # Translators: authentication dialog help 2/4
        _(
          "\n" +
            "<p>The outgoing mail server is generally intended for dial-up connections.\n" +
            "Enter the Internet service provider's SMTP server, such as <b>smtp.provider.com</b>.</p>\n"
        ) +
        # Translators: authentication dialog help 3/4
        _(
          "\n<p>In the <b>User Name</b> field, enter the user name assigned by from your provider.</p>\n"
        ) +
        # Translators: authentication dialog help 4/4
        _("\n<p>Enter your password in the <b>Password</b> field.</p>\n") +
        # Translators: authentication dialog help, 5/4
        _(
          "\n" +
            "<p>Note: For simplicity, only one server is displayed in this dialog,\n" +
            "although there may be more of them in your configuration file.\n" +
            "They will not be lost.</p>\n"
        )
    end

    # @return Help for Downloading dialog
    def DownloadingDialogHelp
      # Translators: downloading dialog help, part 1 of 1
      _(
        "\n" +
          "<p>These are parameters for downloading mail from\n" +
          "a POP or an IMAP server using <b>fetchmail</b>.</p>\n"
      )
    end

    # @return Help for Aliases dialog, with a "man_aliases" hyperlink.
    def AliasesDialogHelp
      # Translators: aliases dialog help, part 1 of 2
      _(
        "\n" +
          "<p>This table redirects mail delivered locally.\n" +
          "Redirect it to another local user (useful for system accounts,\n" +
          "especially for <b>root</b>), to a remote address, or to a list of addresses.</p>\n"
      ) +
        # Translators: aliases dialog help, part 2 of 2
        _(
          "\n" +
            "<p>See the aliases(5) manual page\n" +
            "for a description of advanced features.</p>\n"
        )
    end

    # @return Help for virtual domains dialog
    def VirtualDialogHelp
      # Translators: virtual domains dialog help, part 1 of 2
      _(
        "\n" +
          "<p>This table redirects incoming mail. Unlike the alias table,\n" +
          "it also considers the domain\n" +
          "part of the address.</p>\n"
      ) +
        # Translators: virtual domains dialog help, part 2 of 2
        _(
          "\n" +
            "<p>It allows hosting multiple \"virtual domains\"\n" +
            "on a single machine.</p>\n"
        )
    end
  end
end
