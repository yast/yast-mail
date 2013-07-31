# encoding: utf-8

# File:
#   clients/mail.ycp
#
# Package:
#   Configuration of mail
#
# Summary:
#   Main file
#
# Authors:
#   Peter Varkoly <varkoly@novell.com>
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
#
# Main file for mail configuration. Uses all other files.
#

# @param flag "<b>permanent</b>", "<b>dialup</b>", or "<b>screenshots</b>"<br>
#  <dl>
#  <dt>permanent<dd>preselects permanent connnection
#  <dt>dialup<dd>preselects dial-up connnection
#  <dt>screenshots
#   <dd>uses faked data (see Mail::Fake), enables running the module
#    as non-root. (Uses Mode::screen_shot().)
#  </dl>
module Yast
  class MailClient < Client
    def main
      Yast.import "UI"
      #**
      # <h3>Configuration of the mail</h3>

      textdomain "mail"

      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "CommandLine"

      # The main ()
      Builtins.y2milestone("Mail module started")
      Builtins.y2milestone("----------------------------------------")
      # Command line definition
      @cmdline = {
        # Commandline help title
        # configuration of hosts
        "help"       => _(
          "Mail Server Configuration"
        ),
        "id"         => "mail",
        "guihandler" => fun_ref(method(:Main), "any ()"),
        #    "initialize": Host::Read,
        #    "finish"    : Host::Write, // FIXME
        "actions"    => {
          "setup" => {
            # Commandline command help
            "help"    => _(
              "Set Up the Mail Server Configuration"
            ),
            "handler" => fun_ref(
              method(:Setup),
              "boolean (map <string, string>)"
            )
          }
        }
      }

      @ret = CommandLine.Run(@cmdline)
      Builtins.y2debug("ret=%1", @ret)

      # Finish
      Builtins.y2milestone("Mail module finished")
      deep_copy(@ret)
    end

    # The maske to select the type of the configuration
    def StartDialogHelp
      # Translators: start dialog help, part 1 of 4
      _("<P><B>Mail Server Configuration</B><BR>") +
        # Translators: start dialog help, part 2 of 4
        _(
          "<P>This module will configure and start Postfix and, if necessary, the Cyrus IMAP server.</P>"
        ) +
        # Translators: start dialog help, part 3 of 4
        _(
          "<P><B>Warning:</B></P>\n" +
            "<P>Most home users can use the built-in \n" +
            "features of their email application to send and\n" +
            "receive email. They do not need this module.</P>\n"
        ) +
        # Translators: start dialog help, part 4 of 4
        _(
          "<P>You need Postfix only to store\nemail on your local system or for some special cases.</P>\n"
        )
    end

    def StartDialog(type, first)
      Builtins.y2milestone("Mail configuration type %1", type)

      Wizard.SetScreenShotName("mail-0-start")
      caption = _("Mail Server Configuration")
      tskip_ask = Left(
        CheckBox(Id(:skip_ask), _("Skip this page in the future"))
      )
      status = _("Mail server is not configured.") + "\n" +
        _("Select configuration type according your needs.") + "\n" +
        _(
          "If you want to use sendmail as your MTA, you have to use the Standard configuration."
        ) + "\n" +
        _(
          "The Advanced configuration use LDAP as backend and will configure your system as LDAP-Client and setup an LDAP-Server if necessary."
        )
      if first
        tskip_ask = VSpacing(1)
      else
        if type == "standard"
          status = _(
            "The running mail server configuration is based on the \"Standard\" type."
          ) + "\n" +
            _(
              "It is possible to change to \"Advanced\" settings. This will overwrite all existing settings."
            )
        elsif type == "advanced"
          status = _(
            "The running mail server configuration is based on the \"Advanced\" type."
          ) + "\n" +
            _(
              "It is possible to change to \"Standard\" settings. This will overwrite all existing settings."
            )
        end
      end
      contents = Frame(
        "",
        VBox(
          Left(Label(status)),
          RadioButtonGroup(
            Id(:conf_type),
            VBox(
              VSpacing(1),
              Left(
                RadioButton(Id("standard"), _("Standard"), type == "standard")
              ),
              VSpacing(1),
              Left(
                RadioButton(Id("advanced"), _("Advanced"), type == "advanced")
              ),
              VSpacing(1)
            )
          ),
          tskip_ask,
          VSpacing(1)
        )
      )
      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("mail")
      Wizard.SetContentsButtons(
        caption,
        contents,
        StartDialogHelp(),
        Label.BackButton,
        Label.NextButton
      )

      ret = nil
      sret = nil
      while true
        ret = UI.UserInput
        ret = :abort if ret == :cancel

        break if ret == :back || ret == :abort

        if ret == :next
          if !first
            if Convert.to_boolean(UI.QueryWidget(Id(:skip_ask), :Value))
              SCR.Write(path(".sysconfig.mail.SKIP_ASK"), "yes")
            end
          else
            SCR.Write(path(".sysconfig.mail.SKIP_ASK"), "no")
          end
          sret = Convert.to_string(
            UI.QueryWidget(Id(:conf_type), :CurrentButton)
          )
          if sret == nil
            Popup.Error(_("You have to select a configuration type"))
            next
          end
          Builtins.y2milestone("Mail configuration type %1", sret)
          break
        end
      end
      UI.CloseDialog
      sret
    end

    #**************
    # MAIN ROUTINE
    #**************

    def Main
      # parse arguments
      args = WFM.Args

      # we collect some informations from the system
      ret = nil
      skip_ask = "no"
      conf_type = "undef"
      skip_ask = Convert.to_string(SCR.Read(path(".sysconfig.mail.SKIP_ASK")))
      conf_type = Convert.to_string(
        SCR.Read(path(".sysconfig.mail.CONFIG_TYPE"))
      )
      first_start = false
      local_recipient_maps = Convert.to_map(
        SCR.Read(path(".mail.ldaptable"), "local_recipient_maps")
      )

      if conf_type != "advanced" && conf_type != "standard"
        if local_recipient_maps != nil
          conf_type = "advanced"
        else
          conf_type = "standard"
        end
        first_start = true
      end
      if skip_ask == "no" || skip_ask == nil
        old_conf = conf_type
        conf_type = StartDialog(conf_type, first_start)
        if conf_type == nil
          Builtins.y2milestone("no mail server configuration type")
          return deep_copy(ret)
        end
        first_start = true if old_conf != conf_type
      end

      if conf_type == "advanced"
        Ops.set(args, Builtins.size(args), "setup") if first_start
        ret = WFM.CallFunction("mail-advanced", args)
      else
        ret = WFM.CallFunction("mail-standard", args)
      end
      Builtins.y2milestone("Mail module %1 returned %2", conf_type, ret)

      if ret != nil && ret != :cancel && ret != :abort
        SCR.Write(path(".sysconfig.mail.CONFIG_TYPE"), conf_type)
      end

      nil
    end

    def Setup(options)
      options = deep_copy(options)
      Main()
      true
    end
  end
end

Yast::MailClient.new.main
