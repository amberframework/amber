module CLIFixtures
  def expected_animal_controller
    <<-CONT
    class AnimalController < ApplicationController
      def add
        render("add.ecr")
      end

      def list
        render("list.ecr")
      end

      def remove
        render("remove.ecr")
      end
    end

    CONT
  end

  def expected_post_model_migration
    <<-SQL
    -- +micrate Up
    CREATE TABLE posts (
      id INTEGER NOT NULL PRIMARY KEY,
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
    class Post < Granite::Base
      connection sqlite
      table posts

      belongs_to :user

      column id : Int64, primary: true
      column title : String?
      column body : String?
      column published : Int64?
      column likes : Int64?
    end

    MODEL
  end
end
