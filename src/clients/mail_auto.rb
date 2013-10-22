# encoding: utf-8

# File:
#   mail_auto.ycp
#
# Package:
#   Configuration of mail
#
# Summary:
#   Client for autoinstallation
#
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
#
# This is a client for autoinstallation. It takes its arguments,
# goes through the configuration and return the setting.
# Does not do any changes to the configuration.

# @param first a function
# @return [Object]
# @example map mm = $[ "FAIL_DELAY" : "77" ];
# @example map ret = WFM::CallModule ("mail_auto", [ "Summary", mm ]);
module Yast
  class MailAutoClient < Client
    def main
      Yast.import "UI"
      textdomain "mail"

      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("Mail auto started")

      Yast.import "Mail"
      Yast.import "Mode"
      Yast.include self, "mail/ui.rb"

      @ret = nil
      @func = ""
      @param = {}

      # Fallback for the old calling convention:
      #    Do nothing instead of looping endlessly
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          (Ops.is_map?(WFM.Args(0)) || Ops.is_list?(WFM.Args(0)))
        Builtins.y2error(
          "This new-style module won't work with the old autoyast"
        )
        return [UI.UserInput, WFM.Args(0)]
      end

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

      @abort_block = lambda { false }

      # Import
      if @func == "Import"
        @ret = Mail.Import(@param)
      # Create a  summary
      elsif @func == "Summary"
        @ret = Mail.Summary
      # Reset configuration
      elsif @func == "Reset"
        Mail.Import({})
        Mail.touched = false
        @ret = {}
      elsif @func == "Packages"
        @ret = Mail.AutoPackages
      elsif @func == "Read"
        @ret = Mail.Read(@abort_block)
      # Change configuration (run AutoSequence)
      elsif @func == "Change"
        @ret = MailAutoSequence()
      # Return actual state
      elsif @func == "Export"
        @ret = Mail.Export
      # Return if configuration  was changed
      # return boolean
      elsif @func == "GetModified"
        @ret = Mail.touched
      # Set modified flag
      # return boolean
      elsif @func == "SetModified"
        Mail.touched = true
        @ret = true
      # Write givven settings
      elsif @func == "Write"
        Yast.import "Progress"
        @progress_orig = Progress.set(false)
        @ret = Mail.Write(@abort_block)
        Progress.set(@progress_orig)
        return deep_copy(@ret)
      else
        Builtins.y2error("Unknown function: %1", @func)
        @ret = false
      end

      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("Mail auto finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret) 

      # EOF
    end
  end
end

Yast::MailAutoClient.new.main
