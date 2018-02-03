module CLIFixtures
  def expected_animal_controller
    <<-CONT
    class AnimalController < ApplicationController
      def add
        render("add.slang")
      end

      def list
        render("list.slang")
      end

      def remove
        render("remove.slang")
      end
    end

    CONT
  end

  def expected_post_model_migration
    <<-SQL
    -- +micrate Up
    CREATE TABLE posts (
      id BIGSERIAL PRIMARY KEY,
      title VARCHAR,
      body TEXT,
      published BOOL,
      likes INT,
      user_id BIGINT,
      created_at TIMESTAMP,
      updated_at TIMESTAMP
    );
    CREATE INDEX post_user_id_idx ON posts (user_id);

    -- +micrate Down
    DROP TABLE IF EXISTS posts;

    SQL
  end

  def expected_post_model_spec
    <<-SQL
    require "./spec_helper"
    require "../../src/models/post.cr"

    describe Post do
      Spec.before_each do
        Post.clear
      end
    end

    SQL
  end

  def expected_post_model
    <<-MODEL
    class Post < Granite::ORM::Base
      adapter pg
      table_name posts

      belongs_to :user

      # id : Int64 primary key is created for you
      field title : String
      field body : String
      field published : Bool
      field likes : Int32
      timestamps
    end

    MODEL
  end
end
