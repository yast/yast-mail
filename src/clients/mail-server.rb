# encoding: utf-8

# File:	clients/mail-server.ycp
# Package:	Configuration of mail-server
# Summary:	Main file
# Authors:	Peter Varkoly <varkoly@suse.de>
#
# $Id: mail-server.ycp 19955 2004-10-26 12:28:16Z varkoly $
#
# Main file for mail-server configuration. Uses all other files.
module Yast
  class MailServerClient < Client
    def main
      Yast.import "UI"

      #**
      # <h3>Configuration of mail-server</h3>

      textdomain "mail"

      # The main ()
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("MailServer module started")

      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Summary"
      Yast.import "Popup"
      Yast.import "Label"

      Yast.import "CommandLine"
      Yast.include self, "mail/mail-server_wizards.rb"

      @cmdline_description = {
        "id"         => "mail-server",
        # Command line help text for the mail-server module
        "help"       => _(
          "Configuration of mail server"
        ),
        "guihandler" => fun_ref(method(:MailServerSequence), "any ()"),
        "initialize" => fun_ref(MailServer.method(:Read), "boolean ()"),
        "finish"     => fun_ref(MailServer.method(:Write), "boolean ()"),
        "actions" =>
          # FIXME TODO: fill the functionality description here
          {},
        "options" =>
          # FIXME TODO: fill the option descriptions here
          {},
        "mapping" =>
          # FIXME TODO: fill the mappings of actions and options here
          {}
      }

      #    after merging yast2-mail and yast2-mail-server we have to be
      #    carefull not to corrupt the configuration of the other modul
      if SCR.Read(path(".sysconfig.mail.MAIL_CREATE_CONFIG")) == "yes"
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
          return nil
        end
      end

      # is this proposal or not?
      @propose = false
      @args = WFM.Args
      if Ops.greater_than(Builtins.size(@args), 0)
        if Ops.is_path?(WFM.Args(0)) && WFM.Args(0) == path(".propose")
          Builtins.y2milestone("Using PROPOSE mode")
          @propose = true
        end
      end

      # main ui function
      @ret = nil

      if @propose
        @ret = MailServerAutoSequence()
      else
        @ret = CommandLine.Run(@cmdline_description)
      end
      Builtins.y2debug("ret=%1", @ret)

      # Finish
      Builtins.y2milestone("MailServer module finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret) 

      # EOF
    end
  end
end

Yast::MailServerClient.new.main
