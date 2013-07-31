# encoding: utf-8

# File:	clients/mail-server_proposal.ycp
# Package:	Configuration of mail-server
# Summary:	Proposal function dispatcher.
# Authors:	Peter Varkoly <varkoly@suse.de>
#
# $Id: mail-server_proposal.ycp 19955 2004-10-26 12:28:16Z varkoly $
#
# Proposal function dispatcher for mail-server configuration.
# See source/installation/proposal/proposal-API.txt
module Yast
  class MailServerProposalClient < Client
    def main

      textdomain "mail"

      Yast.import "MailServer"
      Yast.import "Progress"

      # The main ()
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("MailServer proposal started")

      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      # create a textual proposal
      if @func == "MakeProposal"
        @proposal = ""
        @warning = nil
        @warning_level = nil
        @force_reset = Ops.get_boolean(@param, "force_reset", false)

        if @force_reset || !MailServer.proposal_valid
          MailServer.proposal_valid = true
          Progress.off
          MailServer.Read
        end
        @sum = MailServer.Summary
        @proposal = Ops.get_string(@sum, 0, "")
        Progress.on

        @ret = {
          "preformatted_proposal" => @proposal,
          "warning_level"         => @warning_level,
          "warning"               => @warning
        }
      # run the module
      elsif @func == "AskUser"
        @stored = MailServer.Export
        @seq = Convert.to_symbol(
          WFM.CallFunction("mail-server", [path(".propose")])
        )
        MailServer.Import(@stored) if @seq != :next
        Builtins.y2debug("stored=%1", @stored)
        Builtins.y2debug("seq=%1", @seq)
        @ret = { "workflow_sequence" => @seq }
      # create titles
      elsif @func == "Description"
        @ret = {
          # Rich text title for MailServer in proposals
          "rich_text_title" => _(
            "Mail Server"
          ),
          # Menu title for MailServer in proposals
          "menu_title"      => _(
            "&Mail Server"
          ),
          "id"              => "mail-server"
        }
      # write the proposal
      elsif @func == "Write"
        MailServer.Write
      else
        Builtins.y2error("unknown function: %1", @func)
      end

      # Finish
      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("MailServer proposal finished")
      Builtins.y2milestone("----------------------------------------")
      deep_copy(@ret) 

      # EOF
    end
  end
end

Yast::MailServerProposalClient.new.main
