# encoding: utf-8

# Module:
#   Mail configuration
# Summary:
#   Testsuite
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
module Yast
  class ReadwriteClient < Client
    def main
      # testedfiles: Mail.ycp MailTable.pm MailTableInclude.pm Package.ycp PackageSystem.ycp Report.ycp Require.ycp Service.ycp Testsuite.ycp

      Yast.include self, "testsuite.rb"

      @READ = {
        # Runlevel:
        "init"      => {
          "scripts" => {
            "exists"   => true,
            "runlevel" => {
              "sendmail"            => {
                "start" => ["3", "5"],
                "stop"  => ["3", "5"]
              },
              "postfix"             => {
                "start" => ["3", "5"],
                "stop"  => ["3", "5"]
              },
              "amavis"              => {
                "start" => ["3", "5"],
                "stop"  => ["3", "5"]
              },
              "fetchmail"           => {
                "start" => ["3", "5"],
                "stop"  => ["3", "5"]
              },
              "SuSEfirewall2_init"  => { "start" => [] },
              "SuSEfirewall2_setup" => { "start" => [] },
              "SuSEfirewall2_final" => { "start" => [] }
            },
            # their contents is not important for ServiceAdjust
            "comment"  => {
              "sendmail"  => {},
              "postfix"   => {},
              "amavis"    => {},
              "fetchmail" => {}
            }
          }
        },
        # Mail itself:
        "sysconfig" => {
          "mail"     => {
            "MAIL_CREATE_CONFIG"  => "yes",
            "SMTPD_LISTEN_REMOTE" => "yes",
            "FROM_HEADER"         => "foo.test"
          },
          "amavis"   => { "USE_AMAVIS" => "yes" },
          "sendmail" => {
            "SENDMAIL_NOCANONIFY"  => "no",
            "SENDMAIL_EXPENSIVE"   => "no",
            "SENDMAIL_LOCALHOST"   => "",
            "SENDMAIL_SMARTHOST"   => "",
            "MASQUERADE_DOMAINS"   => "",
            # TODO: check for a new default in the installed system?
            # (evade the dummy agent, neededforbuild sendmail)
            "SENDMAIL_ARGS"        => "-L sendmail -Am -bd -q30m -om",
            "SMTP_AUTH_MECHANISMS" => ""
          }
        },
        "mail"      => {
          "sendmail"  => {
            "generics" => { "table" => [] },
            "virtuser" => { "table" => [] },
            "auth"     => {
              "accounts" => [
                {
                  "server"   => "s",
                  "user"     => "u",
                  "password" => "p",
                  "more"     => 1
                }
              ]
            }
          },
          "aliases"   => { "table" => [] },
          "fetchmail" => { "accounts" => [] }
        }
      }

      @WRITE = {}

      @EXECUTE_0 = {
        "target" => {
          "bash"        => 0,
          "bash_output" => { "exit" => 0, "stdout" => "", "stderr" => "" }
        }
      }

      @EXECUTE_1 = {
        "target" => {
          "bash"        => 1,
          "bash_output" => { "exit" => 0, "stdout" => "", "stderr" => "" }
        }
      }

      @EXECUTE_INIT = {
        "target" => {
          "bash"        => 1,
          "bash_output" => {
            "exit"   => 0,
            "stderr" => "",
            "stdout" => "charmap=\"UTF-8\"\n"
          }
        }
      }

      @READ_INIT = {
        "console" => { "CONSOLE_ENCODING" => "en_US.UTF-8" },
        "target"  => { "size" => 1 }
      }

      # added testsuite init, because of firewall
      TESTSUITE_INIT([@READ_INIT, {}, @EXECUTE_INIT], nil)

      Yast.import "Progress"
      Yast.import "Mail"
      Yast.import "MailTable"

      MailTable.SetFileName("aliases", "tests/aliases.out")
      MailTable.SetFileName("sendmail.generics", "tests/generics.out")
      MailTable.SetFileName("sendmail.virtuser", "tests/virtuser.out")


      #    Pkg::FAKE (`IsProvided, $["sendmail": true, "amavis-sendmail": true,
      #			      "amavis-postfix": false]);

      @dont_abort = lambda { false }
      Progress.off
      TEST(
        lambda { Mail.Read(@dont_abort) },
        [
          @READ,
          @WRITE, #rpm amavisd-new
          [
            @EXECUTE_0, #rpm sendmail
            @EXECUTE_0
          ]
        ],
        nil
      )
      Mail.write_only = false
      TEST(
        lambda { Mail.Write(@dont_abort) },
        [
          @READ,
          @WRITE, #sendmail restart
          [
            #EXECUTE_1, //rpm amavis-postfix
            @EXECUTE_0, #SuSEconfig
            @EXECUTE_0, #amavis stop
            @EXECUTE_0, #amavis start
            @EXECUTE_0
          ]
        ],
        nil
      )

      nil
    end
  end
end

Yast::ReadwriteClient.new.main
