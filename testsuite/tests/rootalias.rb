# encoding: utf-8

# Module:
#   NIS client configuration
#
# Summary:
#   Testsuite
#
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
module Yast
  class RootaliasClient < Client
    def main
      Yast.include self, "testsuite.rb"
      TESTSUITE_INIT([{}, {}, {}], nil)
      Yast.import "MailTable"
      Yast.import "MailAliases"

      MailTable.SetFileName("aliases", "tests/aliases.out")

      # the test data is a bit convoluted because formerly
      # the data was read from .mail.{sendmail,postfix}.aliases.table

      @READ_s = {
        # targetpkg:
        "targetpkg" => {
          # sendmail
          "installed" => true
        }
      }

      @READ_p1 = {
        # targetpkg:
        "targetpkg" => {
          # sendmail
          "installed" => false
        }
      }

      @READ_p2 = {
        # targetpkg:
        "targetpkg" => {
          # postfix
          "installed" => true
        }
      }

      @WRITE = {}

      DUMP("sendmail")
      TEST(lambda { MailAliases.GetRootAlias }, [@READ_s], nil)
      TEST(lambda { MailAliases.SetRootAlias("ruut") }, [@READ_s], nil)
      TEST(lambda { MailAliases.SetRootAlias("") }, [@READ_s], nil)

      DUMP("postfix")
      TEST(lambda { MailAliases.GetRootAlias }, [[@READ_p1, @READ_p2]], nil)
      # apparently the dumb^H^H^H^Hdummy aggent reads from the first map
      # while there's input.
      TEST(lambda { MailAliases.SetRootAlias("ruut") }, [[@READ_p1, @READ_p2]], nil)
      TEST(lambda { MailAliases.SetRootAlias("") }, [[@READ_p1, @READ_p2]], nil)

      nil
    end
  end
end

Yast::RootaliasClient.new.main
