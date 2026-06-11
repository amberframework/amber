require "../../spec_helper"

module Amber::Support
  describe Inflector do
    describe ".singularize" do
      it "removes trailing s" do
        Inflector.singularize("users").should eq "user"
        Inflector.singularize("posts").should eq "post"
        Inflector.singularize("comments").should eq "comment"
      end

      it "converts ies to y" do
        Inflector.singularize("categories").should eq "category"
        Inflector.singularize("stories").should eq "story"
        Inflector.singularize("replies").should eq "reply"
      end

      it "handles sses endings" do
        Inflector.singularize("addresses").should eq "address"
        Inflector.singularize("dresses").should eq "dress"
      end

      it "handles ches endings" do
        Inflector.singularize("matches").should eq "match"
        Inflector.singularize("batches").should eq "batch"
      end

      it "handles shes endings" do
        Inflector.singularize("dishes").should eq "dish"
        Inflector.singularize("crashes").should eq "crash"
      end

      it "handles xes endings" do
        Inflector.singularize("boxes").should eq "box"
        Inflector.singularize("indexes").should eq "index"
      end

      it "handles ves endings" do
        Inflector.singularize("wives").should eq "wife"
        Inflector.singularize("knives").should eq "knife"
      end

      it "handles irregular plurals" do
        Inflector.singularize("people").should eq "person"
        Inflector.singularize("children").should eq "child"
        Inflector.singularize("men").should eq "man"
        Inflector.singularize("women").should eq "woman"
        Inflector.singularize("mice").should eq "mouse"
      end

      it "returns empty string for empty input" do
        Inflector.singularize("").should eq ""
      end

      it "handles single character words" do
        Inflector.singularize("s").should eq ""
      end
    end

    describe ".namespace_to_prefix" do
      it "strips leading slashes" do
        Inflector.namespace_to_prefix("/admin").should eq "admin"
      end

      it "strips trailing slashes" do
        Inflector.namespace_to_prefix("admin/").should eq "admin"
      end

      it "replaces inner slashes with underscores" do
        Inflector.namespace_to_prefix("/admin/panel").should eq "admin_panel"
      end

      it "replaces dashes with underscores" do
        Inflector.namespace_to_prefix("/my-admin").should eq "my_admin"
      end

      it "handles complex paths" do
        Inflector.namespace_to_prefix("/api/v1/admin").should eq "api_v1_admin"
      end
    end
  end
end
