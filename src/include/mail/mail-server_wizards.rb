# encoding: utf-8

# File:	include/mail/wizards.ycp
# Package:	Configuration of mail-server
# Summary:	Wizards definitions
# Authors:	Peter Varkoly <varkoly@suse.de>
#
# $Id: wizards.ycp 19955 2004-10-26 12:28:16Z varkoly $
module Yast
  module MailMailServerWizardsInclude
    def initialize_mail_mail_server_wizards(include_target)
      Yast.import "UI"

      textdomain "mail"

      Yast.import "Sequencer"
      Yast.import "Wizard"

      Yast.include include_target, "mail/mail-server_complex.rb"
      Yast.include include_target, "mail/mail-server_dialogs.rb"
    end

    # Main workflow of the mail-server configuration
    # @return sequence result
    def MainSequence
      # FIXME: adapt to your needs
      aliases = { "complex" => lambda { ComplexDialog() } }

      # FIXME: adapt to your needs
      sequence = {
        "ws_start" => "complex",
        "complex"  => { :abort => :abort, :next => :next }
      }

      Sequencer.Run(aliases, sequence)
    end

    # Whole configuration of mail-server
    # @return sequence result
    def MailServerSequence
      aliases = {
        "auth"      => [lambda { AuthorizingDialog() }, true],
        "read"      => [lambda { ReadDialog() }, true],
        "main"      => lambda { MainSequence() },
        "ldapsetup" => [lambda { SetupDialog() }, true],
        "write"     => [lambda { WriteDialog() }, true]
      }

      sequence = {
        "ws_start"  => "auth",
        "ldapsetup" => { :abort => :abort, :next => "auth" },
        "auth"      => {
          :ldapsetup => "ldapsetup",
          :abort     => :abort,
          :next      => "read"
        },
        "read"      => { :abort => :abort, :next => "main" },
        "main"      => { :abort => :abort, :next => "write" },
        "write"     => { :abort => :abort, :next => :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("mail")

      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      deep_copy(ret)
    end

    # Workflow of the LDAP Server/Client setup
    # @return sequence result
    def SetupSequence
      # FIXME: adapt to your needs
      aliases = { "setup" => [lambda { SetupDialog() }, true], "main" => lambda do
        MailServerSequence()
      end }

      # FIXME: adapt to your needs
      sequence = {
        "ws_start" => "setup",
        "setup"    => { :abort => :abort, :next => "main" },
        "main"     => { :abort => :abort, :next => :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("mail")

      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      deep_copy(ret)
    end

    # Whole configuration of mail-server but without reading and writing.
    # For use with autoinstallation.
    # @return sequence result
    def MailServerAutoSequence
      # Initialization dialog caption
      caption = _("Mail Server Configuration")
      # Initialization dialog contents
      contents = Label(_("Initializing..."))

      Wizard.CreateDialog
      Wizard.SetDesktopIcon("mail")
      Wizard.SetContentsButtons(
        caption,
        contents,
        "",
        Label.BackButton,
        Label.NextButton
      )

      ret = MainSequence()

      UI.CloseDialog
      deep_copy(ret)
    end
  end
end
