# encoding: utf-8

# Module:
#   Mail configuration
#
# Summary:
#   Testsuite
#
# Authors:
#   Martin Vidner <mvidner@suse.cz>
#
# $Id$
module Yast
  class MergeTablesClient < Client
    def main
      Yast.include self, "testsuite.rb"
      TESTSUITE_INIT([{}, {}, {}], nil)
      Yast.import "MailAliases"

      @old1 = [
        {
          "comment" => " Basic system aliases that MUST be present.\n",
          "value"   => "root",
          "key"     => "postmaster"
        },
        { "comment" => "", "value" => "postmaster", "key" => "mailer-daemon" },
        { "comment" => " amavis\n", "value" => "root", "key" => "virusalert" },
        {
          "comment" => " General redirections for pseudo accounts in /etc/passwd.\n",
          "value"   => "root",
          "key"     => "administrator"
        },
        { "comment" => "", "value" => "root", "key" => "daemon" },
        { "comment" => "", "value" => "root", "key" => "nobody" },
        {
          "comment" => " \"bin\" used to be in /etc/passwd\n",
          "value"   => "root",
          "key"     => "bin"
        },
        {
          "comment" => " Further well-known aliases for dns/news/ftp/mail/fax/web/gnats.\n",
          "value"   => "news",
          "key"     => "newsadm"
        },
        { "comment" => "", "value" => "news", "key" => "newsadmin" },
        { "comment" => "", "value" => "news", "key" => "usenet" }
      ]
      @new1 = [
        { "key" => "root", "value" => "auser", "comment" => " I am r00t!" },
        { "key" => "B.User", "value" => "buser", "comment" => " blah" },
        { "key" => "usenet", "value" => "root", "comment" => " direct" },
        { "key" => "A.User", "value" => "auser", "comment" => "" },
        { "key" => "newsadmin", "value" => "root", "comment" => " direct" }
      ]

      TEST(lambda { MailAliases.mergeTables([], []) }, [], nil)
      TEST(lambda { MailAliases.mergeTables(@new1, []) }, [], nil)
      TEST(lambda { MailAliases.mergeTables([], @old1) }, [], nil)
      TEST(lambda { MailAliases.mergeTables(@new1, @old1) }, [], nil)

      nil
    end
  end
end

Yast::MergeTablesClient.new.main
