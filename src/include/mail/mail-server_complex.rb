# encoding: utf-8

# File:	include/mail/complex.ycp
# Package:	Configuration of mail-server
# Summary:	Dialogs definitions
# Authors:	Peter Varkoly <varkoly@suse.de>
#
# $Id: complex.ycp 19955 2004-10-26 12:28:16Z varkoly $
module Yast
  module MailMailServerComplexInclude
    def initialize_mail_mail_server_complex(include_target)
      Yast.import "UI"

      textdomain "mail"

      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "Wizard"
      Yast.import "MailServer"
      Yast.import "Progress"

      Yast.include include_target, "mail/mail-server_helps.rb"
      Yast.include include_target, "mail/mail-server_dialogs.rb"
    end

    # Return a modification status
    # @return true if data was modified
    def Modified
      MailServer.Modified
    end

    def PollAbort
      UI.PollInput == :abort
    end

    # Read settings dialog
    # @return `abort if aborted and `next otherwise
    def SetupDialog
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "setup", ""))
      caption = _("Set up the mail server")
      steps = 3
      sl = 3

      Builtins.y2milestone("----- Start MailServer::Setup -----")

      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        "",
        steps,
        [
          # Progress stage 0/3
          _("Read needed packages"),
          # Progress stage 1/3
          _("Read LDAP settings"),
          # Progress stage 2/3
          _("Choose LDAP and CA settings"),
          # Progress stage 3/3
          _("Configure LDAP server and CA management")
        ],
        [
          # Progress stage 0/7
          _("Reading packages..."),
          # Progress stage 1/3
          _("Reading LDAP settings..."),
          # Progress stage 2/3
          _("Choosing LDAP and CA settings..."),
          # Progress stage 3/3
          _("Configuring LDAP server and CA management..."),
          # Progress finished
          _("Finished")
        ],
        ""
      )

      # read  packages
      Progress.NextStage
      return :abort if !MailServer.CheckPackages
      Builtins.sleep(sl)
      # read  packages
      Progress.NextStage
      return :abort if CheckLDAPDialog() != :ok
      Builtins.sleep(sl)
      :next
    end

    # Read settings dialog
    # @return `abort if aborted and `next otherwise
    def ReadDialog
      #    after merging yast2-mail and yast2-mail-server we have to be
      #    carefull not to corrupt the configuration of the other modul
      if !MailServer.setup &&
          SCR.Read(path(".sysconfig.mail.MAIL_CREATE_CONFIG")) == "yes"
        if !Popup.AnyQuestionRichText(
            Label.WarningMsg,
            _("You have configured your MTA without LDAP support.<br>") +
              _("This modul will configure your MTA with LDAP support.<br>") +
              _("This will corrupt your current configuration."),
            80,
            10,
            Label.ContinueButton,
            Label.CancelButton,
            :focus_no
          )
          return :abort
        end
      end

      Wizard.RestoreHelp(Ops.get_string(@HELPS, "read", ""))
      ret = MailServer.Read
      ret ? :next : :abort
    end

    # Write settings dialog
    # @return `abort if aborted and `next otherwise
    def WriteDialog
      Wizard.CreateDialog
      Wizard.SetDesktopIcon("mail")
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "write", ""))
      ret = MailServer.Write
      ret ? :next : :abort
    end
  end
end
