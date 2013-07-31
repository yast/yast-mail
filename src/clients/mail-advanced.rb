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
  class MailAdvancedClient < Client
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
        # "initialize"        : MailServer::CheckPackages,
        # "finish"            : MailServer::Write,
        "actions"    => {
          "setup" => {
            "handler" => fun_ref(method(:SetupMailServer), "boolean ()"),
            "help"    => _("Advanced mail server setup with LDAP back-end")
          }
        },
        "options" =>
          # FIXME TODO: fill the option descriptions here
          {},
        "mapping" =>
          # FIXME TODO: fill the mappings of actions and options here
          {}
      }

      # analyze command line
      @propose = false
      @setup = false
      @args = WFM.Args
      if Ops.greater_than(Builtins.size(@args), 0)
        if Ops.is_path?(WFM.Args(0)) && WFM.Args(0) == path(".propose")
          Builtins.y2milestone("Using PROPOSE mode")
          @propose = true
        end
        if Builtins.contains(@args, "setup")
          Builtins.y2milestone("Using setup mode")
          @setup = true
        end
      end

      # main ui function
      @ret = nil

      if @propose
        @ret = MailServerAutoSequence()
      elsif @setup
        @ret = SetupSequence()
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

    # Command line "setup" commands handler.
    #
    # @param options       map of options from command line
    # @return [Boolean]      true on success
    def SetupMailServer
      ret = SetupSequence()
      true
    end
  end
end

Yast::MailAdvancedClient.new.main
