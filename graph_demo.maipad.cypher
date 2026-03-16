#!maicro
#---
# title: Book Club Knowledge Graph
# emoji: 🕸️
# description: Extend the classic book club schema into a rich Apache AGE knowledge graph. Book nodes auto-sync from SQL via a PostgreSQL trigger — zero extra code. Author nodes are selectively promoted to graph citizens only when they have active catalog entries. Then see how three lines of Cypher replace multi-join SQL for collaborative filtering, bibliographic analysis, and degree-of-separation discovery.
# difficulty: intermediate
# estimated_time: 15m
# graph: bookclub_graph
# tags:
#   - maipad
#   - database
#   - graphql
#   - graph
#   - cypher
#   - starter
# intent: learning
# resources:
#   - type: docs
#     url: /help/reference/graph-database/
#     title: Graph Database Reference
#   - type: docs
#     url: /help/reference/database/
#     title: Database Reference
#---
# maipad-config: {"launch":"run","filename":"graph_demo.maipad.cypher"}

###> TERMINATE BACKGROUND JOBS
#{
# ## Stop Background Jobs
# Before dropping tables, terminate any running async jobs to avoid orphaned
# processes that reference deleted tables.
#}
mutation TerminateJobs {
  DbTerminateJobs {
    terminated_count
  }
}

###> FULL RESET — CLEAN SLATE
#{
# ## Full Reset
# `DbFullReset` drops every user table, associated indexes, Apache AGE graphs,
# and all graph-node sync triggers. System tables are recreated on next `DbReload`.
#}
mutation FullReset {
  DbFullReset
}

###> CREATE BOOK CLUB TABLES
#{
# ## Create Schema
# Four tables: **readers**, **authors**, **books**, and **reviews**. Note the plural
# table names — mAIcro convention. After `DbReload` a full CRUD GraphQL API is
# auto-generated for each table: `bookAdd`, `books(...)`, `bookEdit`, `bookDelete`, etc.
#}
mutation CreateBookClubTables {
  readers: DbCreateTable(
    name: "readers"
    icon: "person-badge"
    description: "Book club members"
    fields: [
      { name: "username", type: String, is_required: true, description: "Unique username" }
      { name: "name", type: String, is_required: true, description: "Display name" }
      { name: "email", type: String, is_sensitive: true, description: "Contact email" }
      { name: "membership_level", type: String, is_required: true, description: "standard or premium" }
    ]
  )

  authors: DbCreateTable(
    name: "authors"
    icon: "pen"
    description: "Book authors"
    fields: [
      { name: "name", type: String, is_required: true, description: "Author full name" }
      { name: "bio", type: String, description: "Short biography" }
      { name: "nationality", type: String, description: "Country of origin" }
      { name: "demography", type: JSON, description: "Genres and additional stats" }
    ]
  )

  books: DbCreateTable(
    name: "books"
    icon: "book"
    description: "Book catalog"
    fields: [
      { name: "title", type: String, is_required: true, description: "Book title" }
      { name: "genre", type: String, is_required: true, description: "Book genre" }
      { name: "author_id", type: ID, description: "Reference to author" }
      { name: "published_year", type: Int, description: "Year of first publication" }
      { name: "synopsis", type: String, has_vector: true, description: "Summary for semantic search" }
      { name: "price", type: Float, description: "Cover price" }
    ]
  )

  reviews: DbCreateTable(
    name: "reviews"
    icon: "chat-square-text"
    description: "Reader book reviews"
    fields: [
      { name: "rating", type: Int, is_required: true, description: "1-5 stars" }
      { name: "review", type: String, is_required: true, description: "Review body" }
      { name: "reader_id", type: ID, description: "Reference to reader" }
      { name: "book_id", type: ID, description: "Reference to book" }
      { name: "review_date", type: String, description: "ISO date" }
    ]
  )
}

###> RELOAD GRAPHQL SCHEMA
#{
# ## Regenerate API
# `DbReload` triggers schema introspection and rebuilds the GraphQL API.
# After this, `bookAdd`, `authorAdd`, `readerAdd`, `reviewAdd` and all list
# queries are live.
#}
mutation ReloadSchema {
  DbReload
}

###> ENABLE THE GRAPH ENGINE
#{
# ## Enable Apache AGE
# `DbFullReset` wipes all system feature flags (including the Cypher enabled
# state), so we re-enable it here — **after** `DbReload` has rebuilt the
# system tables. This step is idempotent: if AGE is already enabled it
# returns `already_enabled` and moves on.
#}
mutation EnableCypher {
  DbEnableCypher {
    age_extension
    status
  }
}

###> ACTIVATE BOOK → GRAPH AUTO-SYNC
#{
# ## The Magic Moment: SQL Insert → Graph Node
# `DbSetGraphSync` installs a PostgreSQL `AFTER INSERT OR DELETE` trigger on
# the `books` table. From this point on, **every `bookAdd` automatically
# creates an AGE node** in `bookclub_graph` carrying `{ table: "books", id: "<sql_uuid>" }`.
#
# You write SQL. The graph looks after itself.
#}
mutation ActivateBookSync {
  DbSetGraphSync(table: "books", graphNode: "auto", graphName: "bookclub_graph")
}

###> SEED AUTHORS — SQL ONLY
#{
# ## Authors Start in SQL
# Authors live in the relational world for now. Graph nodes are *not* created
# automatically — that is deliberate. We promote only featured authors to the
# graph in the next step, and only when they have active catalog entries.
#}
mutation SeedAuthors {
  atwood: authorAdd(data: {
    name: "Margaret Atwood"
    bio: "Canadian author known for speculative and literary fiction."
    nationality: "Canadian"
    demography: "{\"genres\":[\"dystopian\",\"literary\"],\"notable_awards\":[\"Booker Prize\"]}"
  }) { data { id } }

  christie: authorAdd(data: {
    name: "Agatha Christie"
    bio: "English writer and queen of the crime novel."
    nationality: "British"
    demography: "{\"genres\":[\"mystery\",\"crime\"],\"books_published\":66}"
  }) { data { id } }

  asimov: authorAdd(data: {
    name: "Isaac Asimov"
    bio: "Prolific science fiction author and biochemistry professor."
    nationality: "American"
    demography: "{\"genres\":[\"science fiction\"],\"books_published\":500}"
  }) { data { id } }

  leguin: authorAdd(data: {
    name: "Ursula K. Le Guin"
    bio: "American author of literary and speculative fiction."
    nationality: "American"
    demography: "{\"genres\":[\"science fiction\",\"fantasy\"],\"notable_awards\":[\"Hugo\",\"Nebula\"]}"
  }) { data { id } }
}

###> PROMOTE AUTHORS TO GRAPH CITIZENS
#{
# ## Selective Graph Promotion — The Additional Flag Pattern
# Authors are elevated to graph nodes *only* when they have active catalog entries.
# This is explicit, intentional enrichment — not automatic.
#
# Unlike the thin `{table, id}` nodes produced by auto-sync, Author nodes carry
# rich metadata: nationality, active_since, primary_genre. This enables graph-native
# author discovery and genre-based neighbourhood traversal.
#
# In a real system this flag would be set by an editorial workflow:
# "This author is catalog-active — promote to graph."
#}
mutation PromoteAuthorsToGraph {
  atwood_node: CypherNodeCreate(
    graph: "bookclub_graph"
    node: {
      label: "Author"
      properties: "{\"sql_id\": \"{{@@.atwood.id}}\", \"name\": \"Margaret Atwood\", \"nationality\": \"Canadian\", \"primary_genre\": \"dystopian\", \"active_since\": 1964}"
    }
  ) { id }

  christie_node: CypherNodeCreate(
    graph: "bookclub_graph"
    node: {
      label: "Author"
      properties: "{\"sql_id\": \"{{@@.christie.id}}\", \"name\": \"Agatha Christie\", \"nationality\": \"British\", \"primary_genre\": \"mystery\", \"active_since\": 1920}"
    }
  ) { id }

  asimov_node: CypherNodeCreate(
    graph: "bookclub_graph"
    node: {
      label: "Author"
      properties: "{\"sql_id\": \"{{@@.asimov.id}}\", \"name\": \"Isaac Asimov\", \"nationality\": \"American\", \"primary_genre\": \"science fiction\", \"active_since\": 1939}"
    }
  ) { id }

  leguin_node: CypherNodeCreate(
    graph: "bookclub_graph"
    node: {
      label: "Author"
      properties: "{\"sql_id\": \"{{@@.leguin.id}}\", \"name\": \"Ursula K. Le Guin\", \"nationality\": \"American\", \"primary_genre\": \"science fiction\", \"active_since\": 1962}"
    }
  ) { id }
}

###> SEED BOOKS — EACH INSERT FIRES THE GRAPH TRIGGER
#{
# ## Books Flow Automatically into the Graph
# No extra code. No extra mutations. The trigger does the work.
# Six books across three genres → six AGE `:books` nodes, zero effort.
#
# `{{@@.atwood.id}}` interpolates the SQL UUID captured in SEED AUTHORS.
#}
mutation SeedBooks {
  handmaids: bookAdd(data: {
    title: "The Handmaid's Tale"
    genre: "Dystopian"
    author_id: "{{@@.atwood.id}}"
    published_year: 1985
    synopsis: "In a theocratic regime women are stripped of identity and forced into rigid social servitude."
    price: 14.99
  }) { data { id } }

  orient: bookAdd(data: {
    title: "Murder on the Orient Express"
    genre: "Mystery"
    author_id: "{{@@.christie.id}}"
    published_year: 1934
    synopsis: "An elegant detective investigates a murder aboard a luxury train stranded in snow."
    price: 12.50
  }) { data { id } }

  nobody: bookAdd(data: {
    title: "And Then There Were None"
    genre: "Mystery"
    author_id: "{{@@.christie.id}}"
    published_year: 1939
    synopsis: "Ten strangers lured to a remote island begin dying one by one in a locked-room mystery."
    price: 11.99
  }) { data { id } }

  foundation: bookAdd(data: {
    title: "Foundation"
    genre: "Science Fiction"
    author_id: "{{@@.asimov.id}}"
    published_year: 1951
    synopsis: "A mathematician predicts civilizational collapse and devises a plan to shorten the coming dark age."
    price: 16.00
  }) { data { id } }

  irobot: bookAdd(data: {
    title: "I, Robot"
    genre: "Science Fiction"
    author_id: "{{@@.asimov.id}}"
    published_year: 1950
    synopsis: "Nine interlinked stories explore the three laws of robotics and their unintended consequences."
    price: 13.99
  }) { data { id } }

  lefthand: bookAdd(data: {
    title: "The Left Hand of Darkness"
    genre: "Science Fiction"
    author_id: "{{@@.leguin.id}}"
    published_year: 1969
    synopsis: "An envoy visits a genderless civilisation and must navigate its alien politics and philosophy."
    price: 15.00
  }) { data { id } }
}

###> VERIFY BOOK AUTO-SYNC
#{
# ## Did the Trigger Fire?
# Query the graph directly — if auto-sync is working, we should see exactly
# **six `:books` nodes**, one per book inserted above.
# No explicit graph mutations were called. The trigger did it all.
#
# actions:
#   - type: open_cypherpad
#     label: Explore Nodes In CypherPad
#     graph: bookclub_graph
#     query: |
#       MATCH (b:books)
#       RETURN b
#       LIMIT 25
#}
query VerifyBookNodes {
  CypherQuery(
    graph: "bookclub_graph"
    cypher: "MATCH (b:books) RETURN {sql_id: b.id, source_table: b.table} AS row"
  ) {
    rowCount
    data
    columns
  }
}

###> ENRICH BOOK NODES WITH GRAPH METADATA
#{
# ## Lift SQL Data into the Graph — Selective Denormalisation
# Auto-sync creates intentionally thin nodes (`{table, id}`) to avoid data
# duplication. Here we *choose* to enrich those nodes with title, genre, and
# publication year so that Cypher queries later are fully self-contained —
# no SQL join required.
#
# This demonstrates the hybrid model: SQL owns the source of truth, the graph
# receives curated projections optimised for traversal.
#}
mutation EnrichBookNodes {
  handmaids_meta: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (b:books {id: '{{@@.handmaids.id}}'}) SET b.title = 'The Handmaids Tale', b.genre = 'Dystopian', b.year = 1985 RETURN count(*) AS updated"
  ) { rowCount }

  orient_meta: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (b:books {id: '{{@@.orient.id}}'}) SET b.title = 'Murder on the Orient Express', b.genre = 'Mystery', b.year = 1934 RETURN count(*) AS updated"
  ) { rowCount }

  nobody_meta: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (b:books {id: '{{@@.nobody.id}}'}) SET b.title = 'And Then There Were None', b.genre = 'Mystery', b.year = 1939 RETURN count(*) AS updated"
  ) { rowCount }

  foundation_meta: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (b:books {id: '{{@@.foundation.id}}'}) SET b.title = 'Foundation', b.genre = 'Science Fiction', b.year = 1951 RETURN count(*) AS updated"
  ) { rowCount }

  irobot_meta: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (b:books {id: '{{@@.irobot.id}}'}) SET b.title = 'I Robot', b.genre = 'Science Fiction', b.year = 1950 RETURN count(*) AS updated"
  ) { rowCount }

  lefthand_meta: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (b:books {id: '{{@@.lefthand.id}}'}) SET b.title = 'The Left Hand of Darkness', b.genre = 'Science Fiction', b.year = 1969 RETURN count(*) AS updated"
  ) { rowCount }
}

###> SEED READERS — SQL ONLY
#{
# ## Readers in SQL
# Four readers across standard and premium tiers. Their graph representation
# is created in the next step using `CypherNodesBulkCreate`.
#}
mutation SeedReaders {
  alice: readerAdd(data: {
    username: "alice_reads"
    name: "Alice Johnson"
    email: "alice@bookclub.local"
    membership_level: "premium"
  }) { data { id } }

  bob: readerAdd(data: {
    username: "bob_books"
    name: "Bob Chen"
    email: "bob@bookclub.local"
    membership_level: "standard"
  }) { data { id } }

  carol: readerAdd(data: {
    username: "carol_pages"
    name: "Carol Williams"
    email: "carol@bookclub.local"
    membership_level: "premium"
  }) { data { id } }

  dave: readerAdd(data: {
    username: "dave_reads"
    name: "Dave Martinez"
    email: "dave@bookclub.local"
    membership_level: "premium"
  }) { data { id } }
}

###> CREATE READER GRAPH NODES
#{
# ## Readers Join the Graph
# `CypherNodesBulkCreate` adds all four reader nodes in a single operation.
# Each node stores `sql_id` so graph traversal results can be correlated back
# to the relational records at any point.
#}
mutation CreateReaderNodes {
  CypherNodesBulkCreate(
    graph: "bookclub_graph"
    nodes: [
      { label: "Reader", properties: "{\"sql_id\": \"{{@@.alice.id}}\", \"name\": \"Alice Johnson\", \"tier\": \"premium\", \"username\": \"alice_reads\"}" }
      { label: "Reader", properties: "{\"sql_id\": \"{{@@.bob.id}}\", \"name\": \"Bob Chen\", \"tier\": \"standard\", \"username\": \"bob_books\"}" }
      { label: "Reader", properties: "{\"sql_id\": \"{{@@.carol.id}}\", \"name\": \"Carol Williams\", \"tier\": \"premium\", \"username\": \"carol_pages\"}" }
      { label: "Reader", properties: "{\"sql_id\": \"{{@@.dave.id}}\", \"name\": \"Dave Martinez\", \"tier\": \"premium\", \"username\": \"dave_reads\"}" }
    ]
  )
}

###> SEED REVIEWS — SQL
#{
# ## Reviews Belong in SQL
# Reviews have structured ratings, dates, and foreign keys — relational data.
# The graph captures the *relationship* between reader and book; SQL keeps
# the granular review content. Both representations complement each other.
#}
mutation SeedReviews {
  rv_a1: reviewAdd(data: {
    rating: 5
    review: "Chilling and unforgettable. A landmark of speculative fiction."
    reader_id: "{{@@.alice.id}}"
    book_id: "{{@@.handmaids.id}}"
    review_date: "2026-01-05"
  }) { count }

  rv_a2: reviewAdd(data: {
    rating: 4
    review: "Classic sci-fi that holds up remarkably well."
    reader_id: "{{@@.alice.id}}"
    book_id: "{{@@.foundation.id}}"
    review_date: "2026-01-20"
  }) { count }

  rv_a3: reviewAdd(data: {
    rating: 5
    review: "A profound meditation on gender, identity and otherness."
    reader_id: "{{@@.alice.id}}"
    book_id: "{{@@.lefthand.id}}"
    review_date: "2026-02-10"
  }) { count }

  rv_b1: reviewAdd(data: {
    rating: 5
    review: "The perfect locked-room mystery. Clever twist at every turn."
    reader_id: "{{@@.bob.id}}"
    book_id: "{{@@.orient.id}}"
    review_date: "2026-01-14"
  }) { count }

  rv_b2: reviewAdd(data: {
    rating: 3
    review: "Good ideas but the short story format felt rushed."
    reader_id: "{{@@.bob.id}}"
    book_id: "{{@@.irobot.id}}"
    review_date: "2026-02-01"
  }) { count }

  rv_c1: reviewAdd(data: {
    rating: 5
    review: "Epic world-building. The mathematics of history is a brilliant premise."
    reader_id: "{{@@.carol.id}}"
    book_id: "{{@@.foundation.id}}"
    review_date: "2026-01-11"
  }) { count }

  rv_c2: reviewAdd(data: {
    rating: 3
    review: "Important but bleak. Not my preferred reading mood."
    reader_id: "{{@@.carol.id}}"
    book_id: "{{@@.handmaids.id}}"
    review_date: "2026-01-28"
  }) { count }

  rv_c3: reviewAdd(data: {
    rating: 4
    review: "Compulsively readable. Christie was a machine."
    reader_id: "{{@@.carol.id}}"
    book_id: "{{@@.orient.id}}"
    review_date: "2026-02-17"
  }) { count }

  rv_d1: reviewAdd(data: {
    rating: 4
    review: "The most claustrophobic thriller I have ever read."
    reader_id: "{{@@.dave.id}}"
    book_id: "{{@@.nobody.id}}"
    review_date: "2026-01-18"
  }) { count }

  rv_d2: reviewAdd(data: {
    rating: 5
    review: "Le Guin at her absolute best. Expansive in every sense."
    reader_id: "{{@@.dave.id}}"
    book_id: "{{@@.lefthand.id}}"
    review_date: "2026-02-03"
  }) { count }

  rv_d3: reviewAdd(data: {
    rating: 4
    review: "The psychohistory concept alone is worth the read."
    reader_id: "{{@@.dave.id}}"
    book_id: "{{@@.foundation.id}}"
    review_date: "2026-02-14"
  }) { count }
}

###> WIRE AUTHORSHIP EDGES — :WROTE
#{
# ## Authorship as a First-Class Graph Relationship
# Each `:WROTE` edge carries the publication year so the graph can answer
# "what was this author writing in the 1950s?" without ever touching SQL.
#
# MATCH uses `sql_id` on Author nodes (set in PROMOTE AUTHORS) and `id` on
# book nodes (set by the auto-sync trigger). Both values come from
# `{{@@.alias.id}}` interpolation — the same UUIDs from the SQL inserts.
#}
mutation WireWroteEdges {
  atwood_handmaids: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:Author {sql_id: '{{@@.atwood.id}}'}), (b:books {id: '{{@@.handmaids.id}}'}) CREATE (a)-[:WROTE {year: 1985}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  christie_orient: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:Author {sql_id: '{{@@.christie.id}}'}), (b:books {id: '{{@@.orient.id}}'}) CREATE (a)-[:WROTE {year: 1934}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  christie_nobody: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:Author {sql_id: '{{@@.christie.id}}'}), (b:books {id: '{{@@.nobody.id}}'}) CREATE (a)-[:WROTE {year: 1939}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  asimov_foundation: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:Author {sql_id: '{{@@.asimov.id}}'}), (b:books {id: '{{@@.foundation.id}}'}) CREATE (a)-[:WROTE {year: 1951}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  asimov_irobot: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:Author {sql_id: '{{@@.asimov.id}}'}), (b:books {id: '{{@@.irobot.id}}'}) CREATE (a)-[:WROTE {year: 1950}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  leguin_lefthand: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:Author {sql_id: '{{@@.leguin.id}}'}), (b:books {id: '{{@@.lefthand.id}}'}) CREATE (a)-[:WROTE {year: 1969}]->(b) RETURN count(*) AS created"
  ) { rowCount }
}

###> WIRE REVIEW EDGES — :REVIEWED
#{
# ## Reviews as Graph Relationships
# SQL stores the review *data*. The graph stores the review *relationship*.
# The `rating` property on each `:REVIEWED` edge enables rating-weighted
# traversal — shortest path, top-rated neighbourhood, and collaborative
# filtering all use this edge weight naturally.
#}
mutation WireReviewedEdges {
  alice_handmaids: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.alice.id}}'}), (b:books {id: '{{@@.handmaids.id}}'}) CREATE (r)-[:REVIEWED {rating: 5}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  alice_foundation: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.alice.id}}'}), (b:books {id: '{{@@.foundation.id}}'}) CREATE (r)-[:REVIEWED {rating: 4}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  alice_lefthand: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.alice.id}}'}), (b:books {id: '{{@@.lefthand.id}}'}) CREATE (r)-[:REVIEWED {rating: 5}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  bob_orient: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.bob.id}}'}), (b:books {id: '{{@@.orient.id}}'}) CREATE (r)-[:REVIEWED {rating: 5}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  bob_irobot: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.bob.id}}'}), (b:books {id: '{{@@.irobot.id}}'}) CREATE (r)-[:REVIEWED {rating: 3}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  carol_foundation: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.carol.id}}'}), (b:books {id: '{{@@.foundation.id}}'}) CREATE (r)-[:REVIEWED {rating: 5}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  carol_handmaids: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.carol.id}}'}), (b:books {id: '{{@@.handmaids.id}}'}) CREATE (r)-[:REVIEWED {rating: 3}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  carol_orient: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.carol.id}}'}), (b:books {id: '{{@@.orient.id}}'}) CREATE (r)-[:REVIEWED {rating: 4}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  dave_nobody: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.dave.id}}'}), (b:books {id: '{{@@.nobody.id}}'}) CREATE (r)-[:REVIEWED {rating: 4}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  dave_lefthand: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.dave.id}}'}), (b:books {id: '{{@@.lefthand.id}}'}) CREATE (r)-[:REVIEWED {rating: 5}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  dave_foundation: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (r:Reader {sql_id: '{{@@.dave.id}}'}), (b:books {id: '{{@@.foundation.id}}'}) CREATE (r)-[:REVIEWED {rating: 4}]->(b) RETURN count(*) AS created"
  ) { rowCount }
}

###> WIRE GENRE SIMILARITY EDGES — :SIMILAR_TO
#{
# ## Genre Similarity is a Graph-Native Concern
# Connecting books by thematic and genre similarity is inherently a graph
# problem. These `:SIMILAR_TO` edges — with a `score` property — form the
# backbone of a content-based recommendation engine. Zero SQL join tables needed.
#}
mutation WireSimilarityEdges {
  handmaids_lefthand: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:books {id: '{{@@.handmaids.id}}'}), (b:books {id: '{{@@.lefthand.id}}'}) CREATE (a)-[:SIMILAR_TO {reason: 'speculative fiction feminist themes', score: 0.87}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  foundation_irobot: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:books {id: '{{@@.foundation.id}}'}), (b:books {id: '{{@@.irobot.id}}'}) CREATE (a)-[:SIMILAR_TO {reason: 'Asimov universe', score: 0.92}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  foundation_lefthand: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:books {id: '{{@@.foundation.id}}'}), (b:books {id: '{{@@.lefthand.id}}'}) CREATE (a)-[:SIMILAR_TO {reason: 'classic science fiction', score: 0.74}]->(b) RETURN count(*) AS created"
  ) { rowCount }

  orient_nobody: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:books {id: '{{@@.orient.id}}'}), (b:books {id: '{{@@.nobody.id}}'}) CREATE (a)-[:SIMILAR_TO {reason: 'Agatha Christie mystery', score: 0.95}]->(b) RETURN count(*) AS created"
  ) { rowCount }
}

###> ADD DISCOVERY CONTEXT — OUTLETS, OFFERS, EVENTS
#{
# ## Add Adjacent Nodes Worth Discovering Via Expand Neighborhood
# These nodes are intentionally **not** returned by the main analytics queries.
# They enrich the graph so a user can click an Author or Book and use
# Expand Neighborhood to reveal nearby commercial and event context:
# - where books are stocked (`:STOCKS`)
# - active discounts (`:HAS_OFFER`)
# - author appearances (`:APPEARS_AT`)
#}
mutation AddDiscoveryContext {
  citylights: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MERGE (o:Outlet {name: 'CityLights Downtown'}) SET o.city = 'Toronto', o.kind = 'indie bookstore' RETURN count(*) AS updated"
  ) { rowCount }

  pagesnbeans: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MERGE (o:Outlet {name: 'Pages & Beans'}) SET o.city = 'Seattle', o.kind = 'book cafe' RETURN count(*) AS updated"
  ) { rowCount }

  transitbooks: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MERGE (o:Outlet {name: 'Transit Terminal Books'}) SET o.city = 'New York', o.kind = 'travel kiosk' RETURN count(*) AS updated"
  ) { rowCount }

  offer_scifi: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MERGE (of:Offer {code: 'SCIFI15'}) SET of.kind = 'discount', of.percent = 15, of.expires_on = '2026-12-31' RETURN count(*) AS updated"
  ) { rowCount }

  offer_mystery: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MERGE (of:Offer {code: 'MYSTERY10'}) SET of.kind = 'bundle', of.percent = 10, of.expires_on = '2026-09-30' RETURN count(*) AS updated"
  ) { rowCount }

  event_foundation: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MERGE (ev:Event {slug: 'galactic-ideas-night'}) SET ev.title = 'Galactic Ideas Night', ev.starts_at = '2026-05-16T19:00:00Z' RETURN count(*) AS updated"
  ) { rowCount }

  event_mystery: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MERGE (ev:Event {slug: 'murder-mystery-evening'}) SET ev.title = 'Murder Mystery Evening', ev.starts_at = '2026-06-05T18:30:00Z' RETURN count(*) AS updated"
  ) { rowCount }

  link_outlet_stock_foundation: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (o:Outlet {name: 'CityLights Downtown'}), (b:books {title: 'Foundation'}) MERGE (o)-[:STOCKS {stock: 14}]->(b) RETURN count(*) AS linked"
  ) { rowCount }

  link_outlet_stock_handmaids: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (o:Outlet {name: 'Pages & Beans'}), (b:books {title: 'The Handmaids Tale'}) MERGE (o)-[:STOCKS {stock: 9}]->(b) RETURN count(*) AS linked"
  ) { rowCount }

  link_outlet_stock_orient: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (o:Outlet {name: 'Transit Terminal Books'}), (b:books {title: 'Murder on the Orient Express'}) MERGE (o)-[:STOCKS {stock: 20}]->(b) RETURN count(*) AS linked"
  ) { rowCount }

  link_offer_foundation: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (of:Offer {code: 'SCIFI15'}), (b:books {title: 'Foundation'}) MERGE (b)-[:HAS_OFFER]->(of) RETURN count(*) AS linked"
  ) { rowCount }

  link_offer_irobot: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (of:Offer {code: 'SCIFI15'}), (b:books {title: 'I Robot'}) MERGE (b)-[:HAS_OFFER]->(of) RETURN count(*) AS linked"
  ) { rowCount }

  link_offer_orient: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (of:Offer {code: 'MYSTERY10'}), (b:books {title: 'Murder on the Orient Express'}) MERGE (b)-[:HAS_OFFER]->(of) RETURN count(*) AS linked"
  ) { rowCount }

  link_event_author_asimov: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:Author {name: 'Isaac Asimov'}), (ev:Event {slug: 'galactic-ideas-night'}) MERGE (a)-[:APPEARS_AT]->(ev) RETURN count(*) AS linked"
  ) { rowCount }

  link_event_author_christie: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (a:Author {name: 'Agatha Christie'}), (ev:Event {slug: 'murder-mystery-evening'}) MERGE (a)-[:APPEARS_AT]->(ev) RETURN count(*) AS linked"
  ) { rowCount }

  link_event_host_citylights: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (o:Outlet {name: 'CityLights Downtown'}), (ev:Event {slug: 'galactic-ideas-night'}) MERGE (o)-[:HOSTS]->(ev) RETURN count(*) AS linked"
  ) { rowCount }

  link_event_host_pagesnbeans: CypherMutate(
    graph: "bookclub_graph"
    cypher: "MATCH (o:Outlet {name: 'Pages & Beans'}), (ev:Event {slug: 'murder-mystery-evening'}) MERGE (o)-[:HOSTS]->(ev) RETURN count(*) AS linked"
  ) { rowCount }
}

###> GRAPH SNAPSHOT — STATS
#{
# ## What Does the Graph Contain?
# `CypherStats` returns a live count of nodes, edges, labels, and edge types.
# Expected now includes additional discovery context labels such as
# `Outlet`, `Offer`, and `Event` with relationships like `:STOCKS`,
# `:HAS_OFFER`, `:APPEARS_AT`, and `:HOSTS`.
#}
query GraphSnapshot {
  CypherStats(graph: "bookclub_graph") {
    name
    nodeCount
    edgeCount
    labels
    edgeTypes
  }
}

###> QUERY: AUTHOR BIBLIOGRAPHY WITH RATINGS
#{
# ## Who Wrote What, and How Was It Received?
# A single MATCH traversal replaces a three-way SQL JOIN across `authors`,
# `books`, and `reviews`. The graph result includes author name, book title,
# publication year, average reader rating, and total review count.
#
# Try this in SQL. It requires three joins, a GROUP BY, and careful NULL handling.
# In Cypher it is four lines.
#
# actions:
#   - type: open_cypherpad
#     label: Open Bibliography Query
#     graph: bookclub_graph
#     query: |
#       MATCH (a:Author)-[w:WROTE]->(b:books)<-[rv:REVIEWED]-(r:Reader)
#       WITH a, w, b, rv, r
#       RETURN {
#         author: a,
#         wrote: w,
#         book: b,
#         reader: r,
#         reviewed: rv,
#         rating: rv.rating
#       } AS row
#       ORDER BY a.name, b.title, rv.rating DESC
#   - type: open_cypherpad
#     label: Open Author Event & Venue Context
#     graph: bookclub_graph
#     query: |
#       MATCH (a:Author)-[wa:WROTE]->(b:books)
#       OPTIONAL MATCH (a)-[ap:APPEARS_AT]->(ev:Event)<-[hs:HOSTS]-(o:Outlet)
#       RETURN {
#         author: a,
#         wrote: wa,
#         book: b,
#         appears_at: ap,
#         event: ev,
#         hosted_by: hs,
#         outlet: o
#       } AS row
#       ORDER BY a.name, b.title
#}
query AuthorBibliography {
  CypherQuery(
    graph: "bookclub_graph"
    cypher: """
      MATCH (a:Author)-[:WROTE]->(b:books)<-[rv:REVIEWED]-(:Reader)
      WITH a.name AS author, b.title AS book, b.year AS published,
           avg(rv.rating) AS avg_rating, count(rv) AS reviews
      RETURN {
        author: author,
        book: book,
        published: published,
        avg_rating: avg_rating,
        reviews: reviews
      } AS row
      ORDER BY author, avg_rating DESC
    """
  ) {
    rowCount
    data
    columns
    executionTimeMs
  }
}

###> QUERY: COLLABORATIVE FILTERING — RECOMMEND FOR ALICE
#{
# ## Recommendation Engine in Four Lines of Cypher
# **The SQL equivalent requires a correlated subquery, two self-joins on the
# reviews table, a NOT IN filter, and a COUNT aggregation.**
#
# Pattern: find readers who reviewed books Alice liked, surface books those
# readers also reviewed that Alice has not yet seen, rank by peer overlap.
#
# Alice reviewed: The Handmaid's Tale, Foundation, The Left Hand of Darkness.
# Expected recommendations: Murder on the Orient Express (high peer overlap)
# and And Then There Were None.
#
# actions:
#   - type: open_cypherpad
#     label: Open Recommendation Query
#     graph: bookclub_graph
#     query: |
#       MATCH (me:Reader {username: 'alice_reads'})-[:REVIEWED]->(seen:books)
#             <-[:REVIEWED]-(peer:Reader)-[:REVIEWED]->(rec:books)
#       WHERE me <> peer
#       WITH rec.title AS recommended, rec.genre AS genre,
#            count(DISTINCT peer) AS peer_overlap
#       RETURN {
#         recommended: recommended,
#         genre: genre,
#         peer_overlap: peer_overlap
#       } AS row
#       ORDER BY peer_overlap DESC
#       LIMIT 5
#   - type: open_cypherpad
#     label: Open Recommendation + Offers
#     graph: bookclub_graph
#     query: |
#       MATCH (me:Reader {username: 'alice_reads'})-[:REVIEWED]->(:books)<-[:REVIEWED]-(peer:Reader)-[:REVIEWED]->(rec:books)
#       WHERE me <> peer
#       WITH rec, count(DISTINCT peer) AS peer_overlap
#       OPTIONAL MATCH (rec)-[ho:HAS_OFFER]->(of:Offer)
#       OPTIONAL MATCH (out:Outlet)-[st:STOCKS]->(rec)
#       RETURN {
#         book: rec,
#         has_offer: ho,
#         offer: of,
#         stocked_at: st,
#         outlet: out,
#         peer_overlap: peer_overlap
#       } AS row
#       ORDER BY peer_overlap DESC, rec.title
#       LIMIT 10
#}
query RecommendForAlice {
  CypherQuery(
    graph: "bookclub_graph"
    cypher: """
      MATCH (me)-[:REVIEWED]->(seen)<-[:REVIEWED]-(peer)-[:REVIEWED]->(rec)
      WHERE me.sql_id = '{{@@.alice.id}}' AND me <> peer
        AND rec.title IS NOT NULL
      WITH rec.title AS recommended, rec.genre AS genre,
           count(DISTINCT peer) AS peer_overlap
      RETURN recommended + ' | ' + genre + ' | peers=' + toString(peer_overlap) AS row
      ORDER BY peer_overlap DESC
      LIMIT 5
    """
  ) {
    rowCount
    data
    columns
    executionTimeMs
  }
}

###> QUERY: DEGREES OF SEPARATION
#{
# ## How Connected Are Alice and Dave?
# `shortestPath` finds the minimum chain linking two readers through any
# combination of edges — shared books, authorship, or similarity.
#
# Alice and Dave both reviewed Foundation and The Left Hand of Darkness,
# so the expected answer is **2 hops**:
# `(Alice)-[:REVIEWED]->(The Left Hand of Darkness)<-[:REVIEWED]-(Dave)`
#
# Achieving this algorithmically in SQL requires recursive CTEs or a
# dedicated graph library. In Cypher it is one function call.
#}
query DegreesOfSeparation {
  CypherQuery(
    graph: "bookclub_graph"
    cypher: """
      MATCH path = (alice:Reader {sql_id: '{{@@.alice.id}}'})-[*1..6]-(dave:Reader {sql_id: '{{@@.dave.id}}'})
      RETURN length(path) AS row
      ORDER BY length(path) ASC
      LIMIT 1
    """
  ) {
    rowCount
    data
    columns
    executionTimeMs
  }
}

###> QUERY: GENRE NEIGHBOURHOOD
#{
# ## Explore What Readers in a Genre Also Love
# Starting from a Science Fiction book, traverse `:SIMILAR_TO` edges and
# gather all readers who reviewed those neighbouring books. This is the
# seed for a genre-based discovery feed — pure graph, zero SQL.
#
# actions:
#   - type: open_cypherpad
#     label: Open Genre Neighbourhood Query
#     graph: bookclub_graph
#     query: |
#       MATCH (start:books {title: 'Foundation'})-[sim:SIMILAR_TO*1..2]->(neighbour:books)<-[rv:REVIEWED]-(r:Reader)
#       UNWIND sim AS s
#       RETURN {
#         start: start,
#         similar_to: s,
#         neighbour: neighbour,
#         reader: r,
#         reviewed: rv
#       } AS row
#       ORDER BY neighbour.title, rv.rating DESC
#}
query GenreNeighbourhood {
  CypherQuery(
    graph: "bookclub_graph"
    cypher: """
      MATCH (start:books {id: '{{@@.foundation.id}}'})-[:SIMILAR_TO*1..2]->(neighbour:books)<-[rv:REVIEWED]-(r:Reader)
      RETURN {
        neighbour_book: neighbour.title,
        genre: neighbour.genre,
        reader: r.name,
        rating: rv.rating
      } AS row
      ORDER BY neighbour.title, rv.rating DESC
    """
  ) {
    rowCount
    data
    columns
    executionTimeMs
  }
}
