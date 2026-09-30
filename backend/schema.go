package main

import (
	"database/sql"
	"fmt"
	"strings"
)

// SchemaProvider is implemented by relational drivers that expose metadata for
// SQL completion. Keeping it separate from DatabaseDriver lets non-relational
// drivers keep their existing contract.
type SchemaProvider interface {
	Schema() (SchemaResult, error)
}

type SchemaResult struct {
	Tables []SchemaTable `json:"tables"`
}

type SchemaTable struct {
	Schema  string         `json:"schema,omitempty"`
	Name    string         `json:"name"`
	Type    string         `json:"type"`
	Columns []SchemaColumn `json:"columns"`
}

type SchemaColumn struct {
	Name     string `json:"name"`
	DataType string `json:"data_type,omitempty"`
	Nullable bool   `json:"nullable"`
}

func (d *PostgresDriver) Schema() (SchemaResult, error) {
	const query = `
		SELECT t.table_schema, t.table_name, t.table_type,
		       c.column_name, c.data_type, c.is_nullable
		FROM information_schema.tables AS t
		LEFT JOIN information_schema.columns AS c
		  ON c.table_schema = t.table_schema
		 AND c.table_name = t.table_name
		WHERE t.table_schema NOT IN ('pg_catalog', 'information_schema')
		ORDER BY t.table_schema, t.table_name, c.ordinal_position`

	return loadInformationSchema(d.db, query)
}

func (d *MySQLDriver) Schema() (SchemaResult, error) {
	const query = `
		SELECT t.table_schema, t.table_name, t.table_type,
		       c.column_name, c.data_type, c.is_nullable
		FROM information_schema.tables AS t
		LEFT JOIN information_schema.columns AS c
		  ON c.table_schema = t.table_schema
		 AND c.table_name = t.table_name
		WHERE t.table_schema = DATABASE()
		ORDER BY t.table_name, c.ordinal_position`

	return loadInformationSchema(d.db, query)
}

func loadInformationSchema(db *sql.DB, query string) (SchemaResult, error) {
	rows, err := db.Query(query)
	if err != nil {
		return SchemaResult{}, err
	}
	defer rows.Close()

	result := SchemaResult{Tables: make([]SchemaTable, 0)}
	tableIndexes := make(map[string]int)

	for rows.Next() {
		var schemaName, tableName, tableType string
		var columnName, dataType, nullable sql.NullString
		if err := rows.Scan(&schemaName, &tableName, &tableType, &columnName, &dataType, &nullable); err != nil {
			return SchemaResult{}, err
		}

		key := schemaName + "\x00" + tableName
		index, exists := tableIndexes[key]
		if !exists {
			index = len(result.Tables)
			tableIndexes[key] = index
			result.Tables = append(result.Tables, SchemaTable{
				Schema:  schemaName,
				Name:    tableName,
				Type:    normalizeTableType(tableType),
				Columns: make([]SchemaColumn, 0),
			})
		}

		if columnName.Valid {
			result.Tables[index].Columns = append(result.Tables[index].Columns, SchemaColumn{
				Name:     columnName.String,
				DataType: dataType.String,
				Nullable: strings.EqualFold(nullable.String, "YES"),
			})
		}
	}

	if err := rows.Err(); err != nil {
		return SchemaResult{}, err
	}
	return result, nil
}

func (d *SQLiteDriver) Schema() (SchemaResult, error) {
	rows, err := d.db.Query(`
		SELECT name, type
		FROM sqlite_master
		WHERE type IN ('table', 'view')
		  AND name NOT LIKE 'sqlite_%'
		ORDER BY name`)
	if err != nil {
		return SchemaResult{}, err
	}
	defer rows.Close()

	tables := make([]SchemaTable, 0)
	for rows.Next() {
		var table SchemaTable
		if err := rows.Scan(&table.Name, &table.Type); err != nil {
			return SchemaResult{}, err
		}
		table.Columns = make([]SchemaColumn, 0)
		tables = append(tables, table)
	}
	if err := rows.Err(); err != nil {
		return SchemaResult{}, err
	}

	for index := range tables {
		columns, err := loadSQLiteColumns(d.db, tables[index].Name)
		if err != nil {
			return SchemaResult{}, err
		}
		tables[index].Columns = columns
	}

	return SchemaResult{Tables: tables}, nil
}

func loadSQLiteColumns(db *sql.DB, tableName string) ([]SchemaColumn, error) {
	escapedName := strings.ReplaceAll(tableName, "'", "''")
	rows, err := db.Query(fmt.Sprintf("PRAGMA table_info('%s')", escapedName))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	columns := make([]SchemaColumn, 0)
	for rows.Next() {
		var id, notNull, primaryKey int
		var name, dataType string
		var defaultValue interface{}
		if err := rows.Scan(&id, &name, &dataType, &notNull, &defaultValue, &primaryKey); err != nil {
			return nil, err
		}
		columns = append(columns, SchemaColumn{
			Name:     name,
			DataType: dataType,
			Nullable: notNull == 0 && primaryKey == 0,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return columns, nil
}

func normalizeTableType(tableType string) string {
	if strings.EqualFold(tableType, "VIEW") {
		return "view"
	}
	return "table"
}
