\c api_db;

CREATE TABLE a_block_element (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  text JSONB
);

INSERT INTO a_block_element (name, text) VALUES
('Element 1', '{"key1": "value1"}'),
('Element 2', '{"key2": "value2"}');