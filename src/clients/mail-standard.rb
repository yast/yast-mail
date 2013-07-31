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
#   Martin Vidner <mvidner@suse.cz>
#   Peter Varkoly <varkoly@novell.com>
#
# $Id: mail.ycp 37642 2007-04-20 19:06:52Z varkoly $
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
  class MailStandardClient < Client
    def main
      Yast.import "UI"
      #**
      # <h3>Configuration of the mail</h3>

      textdomain "mail"

      Yast.import "CommandLine"
      Yast.import "Mail"
      Yast.import "RichText"
      Yast.include self, "mail/ui.rb"

      # The main ()
      Builtins.y2milestone("Mail standard module started")
      Builtins.y2milestone("----------------------------------------")

      # parse arguments
      @args = WFM.Args
      @first_arg = Ops.get_string(@args, 0, "")
      if @first_arg == "permanent"
        @preselect_connection_type = :permanent
      elsif @first_arg == "dialup"
        @preselect_connection_type = :dialup
      end


      @cmdline_description = {
        "id"         => "mail",
        # Command line help text for the mail module
        "help"       => _(
          "Configuration of mail"
        ),
        "guihandler" => fun_ref(method(:MailSequence), "symbol ()"),
        "initialize" => fun_ref(method(:MailRead), "boolean ()"),
        "finish"     => fun_ref(
          Mail.method(:Write),
          "boolean (block <boolean>)"
        ),
        "actions"    => {
          "summary" => {
            "handler" => fun_ref(method(:MailSummaryHandler), "boolean (map)"),
            # command line action help
            "help"    => _(
              "Mail configuration summary"
            )
          }
        },
        "mappings"   => { "summary" => [] }
      }
      # main ui function
      @ret = @preselect_connection_type == nil ?
        CommandLine.Run(@cmdline_description) :
        MailSequence()
      Builtins.y2debug("ret == %1", @ret)

      # Finish
      Builtins.y2milestone("Mail standard module finished")
      deep_copy(@ret)
    end

    # CLI action handler.
    # Print summary in command line
    # @param [Hash] options command options
    # @return false so that Write is not called in non-interactive mode
    def MailSummaryHandler(options)
      options = deep_copy(options)
      CommandLine.Print(RichText.Rich2Plain(Mail.Summary))
      false
    end

    # CLI initializer.
    # @return whether successful
    def MailRead
      callback = lambda { false }
      Mail.Read(callback)
    end
  end
end

Yast::MailStandardClient.new.main
