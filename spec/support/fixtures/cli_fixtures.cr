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
    class Post < ApplicationModel
      with_timestamps
      mapping(
        id: Primary32,
        title: { type: String? },
        body: { type: String? },
        published: { type: Bool? },
        likes: { type: Int32? },
        created_at: { type: Time? },
        updated_at: { type: Time? }
      )

      belongs_to :user
    end

    MODEL
  end
end
