# encoding: utf-8

# File:	clients/mail-server_auto.ycp
# Package:	Configuration of mail-server
# Summary:	Client for autoinstallation
# Authors:	Peter Varkoly <varkoly@suse.de>
#
# $Id: mail-server_auto.ycp 19955 2004-10-26 12:28:16Z varkoly $
#
# This is a client for autoinstallation. It takes its arguments,
# goes through the configuration and return the setting.
# Does not do any changes to the configuration.

# @param function to execute
# @param map/list of mail-server settings
# @return [Hash] edited settings, Summary or boolean on success depending on called function
# @example map mm = $[ "FAIL_DELAY" : "77" ];
# @example map ret = WFM::CallFunction ("mail-server_auto", [ "Summary", mm ]);
module Yast
  class MailServerAutoClient < Client
    def main
      Yast.import "UI"

      textdomain "mail"

      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("MailServer auto started")

      Yast.import "MailServer"
      Yast.include self, "mail/mail-server_wizards.rb"

      @ret = nil
      @func = ""
      @param = {}

      # Check arguments
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))
        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @param = Convert.to_map(WFM.Args(1))
        end
      end
      Builtins.y2debug("func=%1", @func)
      Builtins.y2debug("param=%1", @param)

      # Create a summary
      if @func == "Summary"
        @ret = Ops.get_string(MailServer.Summary, 0, "")
      # Reset configuration
      elsif @func == "Reset"
        MailServer.Import({})
        @ret = {}
      # Change configuration (run AutoSequence)
      elsif @func == "Change"
        @ret = MailServerAutoSequence()
      # Import configuration
      elsif @func == "Import"
        @ret = MailServer.Import(@param)
      # Return actual state
      elsif @func == "Export"
        @ret = MailServer.Export
      # Return needed packages
      elsif @func == "Packages"
        @ret = MailServer.AutoPackages
      # Read current state
      elsif @func == "Read"
        Yast.import "Progress"
        Progress.off
        @ret = MailServer.Read
        Progress.on
      # Write givven settings
      elsif @func == "Write"
        Yast.import "Progress"
        Progress.off
        MailServer.write_only = true
        @ret = MailServer.Write
        Progress.on
      else
        Builtins.y2error("Unknown function: %1", @func)
        @ret = false
      end

      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("MailServer auto finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret) 

      # EOF
    end
  end
end

Yast::MailServerAutoClient.new.main
