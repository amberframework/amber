require "../../../spec_helper"
require "./migration_spec_helper"

module Amber::CLI::Jennifer
  describe Migration do
    described_class = Amber::CLI::Jennifer::Migration

    describe ".build" do
      context "with empty fields" do
        it "builds unspecified migration for non new table migration name" do
          described_class.build("add_field_to_tables", %w()).is_a?(Amber::CLI::Jennifer::Migration).should be_true
          described_class.build("remove_field_from_tables", %w()).is_a?(Amber::CLI::Jennifer::Migration).should be_true
          described_class.build("some_gibberish", %w()).is_a?(Amber::CLI::Jennifer::Migration).should be_true
        end

        it "builds new table migration for new migration name pattern" do
          described_class.build("create_tables", %w()).is_a?(Amber::CLI::Jennifer::CreateTableMigration).should be_true
        end
      end

      context "with new table migration name pattern" do
        it do
          described_class.build("create_tables", %w(name:string))
            .is_a?(Amber::CLI::Jennifer::CreateTableMigration).should be_true
        end

        it "correctly sets table name" do
          described_class.build("create_tables", %w(field:string))
            .as(Amber::CLI::Jennifer::CreateTableMigration)
            .table_name.should eq("tables")
        end
      end

      context "with add new column migration name pattern" do
        it do
          migration = described_class.build("add_field_to_tables", %w(field:string))
          migration.is_a?(Amber::CLI::Jennifer::ChangeColumnsMigration).should be_true
          migration.as(Amber::CLI::Jennifer::ChangeColumnsMigration).add?.should be_true
        end

        it "correctly sets table name" do
          described_class.build("add_field_to_tables", %w(field:string))
            .as(Amber::CLI::Jennifer::ChangeColumnsMigration)
            .table_name.should eq("tables")
        end
      end

      context "with remove column migration name pattern" do
        it do
          migration = described_class.build("remove_field_from_tables", %w(field:string))
          migration.is_a?(Amber::CLI::Jennifer::ChangeColumnsMigration).should be_true
          migration.as(Amber::CLI::Jennifer::ChangeColumnsMigration).remove?.should be_true
        end

        it "correctly sets table name" do
          described_class.build("add_field_to_tables", %w(field:string))
            .as(Amber::CLI::Jennifer::ChangeColumnsMigration)
            .table_name.should eq("tables")
        end
      end
    end

    describe "#render" do
      migration = described_class.new("some_migration", %w(field:string))
      migration_file = MigrationSpecHelper.text_for(migration)

      it do
        migration_file.should contain "class SomeMigration < Jennifer::Migration::Base"
      end

      it do
        migration_file.should contain "def up"
      end

      it do
        migration_file.should contain "def down"
      end
    end
  end

  describe CreateTableMigration do
    describe "#render" do
      migration = Amber::CLI::Jennifer::CreateTableMigration.new("create_users", %w(name:string owner:ref admin:bool))
      migration_file = MigrationSpecHelper.text_for(migration)

      it do
        migration_file.should contain "class CreateUser < Jennifer::Migration::Base"
      end

      it do
        migration_file.should contain <<-FILE
          def up
            create_table(:users) do |t|
              t.string :name
              t.reference :owner
              t.bool :admin
              t.timestamps
            end
          end
        FILE
      end

      it do
        migration_file.should contain <<-FILE
          def down
            drop_table :users
          end
        FILE
      end
    end
  end

  describe ChangeColumnsMigration do
    describe "#render" do
      describe "adding columns" do
        migration = Amber::CLI::Jennifer::ChangeColumnsMigration.new("add_columns_to_users", %w(name:string owner:ref admin:bool), :add)
        migration_file = MigrationSpecHelper.text_for(migration)

        it do
          migration_file.should contain "class AddColumnsToUser < Jennifer::Migration::Base"
        end

        it do
          migration_file.should contain <<-FILE
            def up
              change_table(:users) do |t|
                t.add_column :name, :string
                t.add_column :owner, :reference
                t.add_column :admin, :bool
              end
            end
          FILE
        end

        it do
          migration_file.should contain <<-FILE
            def down
              change_table(:users) do |t|
                t.drop_column :name
                t.drop_column :owner
                t.drop_column :admin
              end
            end
          FILE
        end
      end

      describe "removing columns" do
        migration = Amber::CLI::Jennifer::ChangeColumnsMigration.new("remove_columns_from_users", %w(name:string owner:ref admin:bool), :remove)
        migration_file = MigrationSpecHelper.text_for(migration)

        it do
          migration_file.should contain "class RemoveColumnsFromUser < Jennifer::Migration::Base"
        end

        it do
          migration_file.should contain <<-FILE
            def up
              change_table(:users) do |t|
                t.drop_column :name
                t.drop_column :owner
                t.drop_column :admin
              end
            end
          FILE
        end

        it do
          migration_file.should contain <<-FILE
            def down
              change_table(:users) do |t|
                t.add_column :name, :string
                t.add_column :owner, :reference
                t.add_column :admin, :bool
              end
            end
          FILE
        end
      end
    end
  end
end
