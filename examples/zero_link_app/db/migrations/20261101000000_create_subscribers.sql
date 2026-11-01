-- +micrate Up
CREATE TABLE subscribers (
  id BIGSERIAL PRIMARY KEY,
  email_address VARCHAR NOT NULL,
  first_name VARCHAR,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- +micrate Down
DROP TABLE IF EXISTS subscribers;
