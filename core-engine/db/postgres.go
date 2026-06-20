package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib" // Registra el driver de postgres
)

type PostgresClient struct {
	DB *sql.DB
}

func NewPostgresClient(db *sql.DB) DatabaseClient {
	return &PostgresClient{DB: db}
}

func (p *PostgresClient) Connect(ctx context.Context, config ConnectRequest) error {
	// Construir connection string sin database si está vacío (conectar al motor)
	dbName := config.Database
	if dbName == "" {
		dbName = "postgres" // BD por defecto para conectar al motor
	}
	
	connStr := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		config.Host, config.Port, config.Username, config.Password, dbName, config.SSLMode)
	
	db, err := sql.Open("pgx", connStr)
	if err != nil {
		return err
	}

	if err := db.PingContext(ctx); err != nil {
		return err
	}

	p.DB = db
	return nil
}

func (p *PostgresClient) Disconnect() error {
	if p.DB != nil {
		return p.DB.Close()
	}
	return nil
}

func (p *PostgresClient) GetDatabases(ctx context.Context) ([]DatabaseInfo, error) {
	query := `
		SELECT datname, datdba, encoding, datcollate, datistemplate
		FROM pg_database
		WHERE datistemplate = false
		ORDER BY datname;
	`
	rows, err := p.DB.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var databases []DatabaseInfo
	for rows.Next() {
		var db DatabaseInfo
		var ownerOid int
		var encodingInt int
		var isTemplate bool
		if err := rows.Scan(&db.Name, &ownerOid, &encodingInt, &db.Collation, &isTemplate); err != nil {
			return nil, err
		}
		db.IsDefault = db.Name == "postgres"
		databases = append(databases, db)
	}
	return databases, nil
}

func (p *PostgresClient) GetTables(ctx context.Context, schema string) ([]Table, error) {
	if schema == "" {
		schema = "public"
	}
	query := `SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_type = 'BASE TABLE' ORDER BY table_name;`
	rows, err := p.DB.QueryContext(ctx, query, schema)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tables []Table
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		tables = append(tables, Table{Name: name})
	}
	return tables, nil
}

func (p *PostgresClient) ExecuteQuery(ctx context.Context, query string) (*QueryResult, error) {
	start := time.Now()

	// Detectar si es SELECT o SHOW (queries que retornan datos)
	upperQuery := strings.TrimSpace(strings.ToUpper(query))
	isSelect := strings.HasPrefix(upperQuery, "SELECT") ||
		strings.HasPrefix(upperQuery, "SHOW") ||
		strings.HasPrefix(upperQuery, "WITH") ||
		strings.HasPrefix(upperQuery, "EXPLAIN")

	if isSelect {
		rows, err := p.DB.QueryContext(ctx, query)
		if err != nil {
			return nil, err
		}
		defer rows.Close()

		columns, err := rows.Columns()
		if err != nil {
			return nil, err
		}

		var result [][]interface{}
		for rows.Next() {
			values := make([]interface{}, len(columns))
			valuePtrs := make([]interface{}, len(columns))
			for i := range columns {
				valuePtrs[i] = &values[i]
			}

			if err := rows.Scan(valuePtrs...); err != nil {
				return nil, err
			}

			rowValues := make([]interface{}, len(columns))
			for i, val := range values {
				if b, ok := val.([]byte); ok {
					rowValues[i] = string(b)
				} else {
					rowValues[i] = val
				}
			}
			result = append(result, rowValues)
		}

		return &QueryResult{
			IsSelect:    true,
			Columns:     columns,
			Rows:        result,
			RowCount:    len(result),
			TotalRows:   len(result),
			ExecutionMs: time.Since(start).Milliseconds(),
		}, nil
	}

	// Para INSERT, UPDATE, DELETE, DDL, etc.
	result, err := p.DB.ExecContext(ctx, query)
	if err != nil {
		return nil, err
	}

	rowsAffected, _ := result.RowsAffected()

	return &QueryResult{
		IsSelect:     false,
		RowsAffected: rowsAffected,
		Message:      fmt.Sprintf("Query ejecutada. %d filas afectadas.", rowsAffected),
		ExecutionMs:  time.Since(start).Milliseconds(),
	}, nil
}

func (p *PostgresClient) GetTableData(ctx context.Context, opts TableDataOptions) (*QueryResult, error) {
	start := time.Now()
	
	safeTableName := sanitizeTableName(opts.TableName)
	if safeTableName == "" {
		return nil, fmt.Errorf("nombre de tabla inválido")
	}

	limit := opts.Limit
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	offset := opts.Offset
	if offset < 0 {
		offset = 0
	}

	// Build WHERE clause for search
	var whereClause string
	var args []interface{}
	argIndex := 1

	if opts.Search != "" {
		// Get columns to search in
		colQuery := `SELECT column_name FROM information_schema.columns WHERE table_name = $1 AND table_schema = 'public'`
		rows, err := p.DB.QueryContext(ctx, colQuery, safeTableName)
		if err != nil {
			return nil, err
		}
		defer rows.Close()

		var columns []string
		for rows.Next() {
			var col string
			if err := rows.Scan(&col); err != nil {
				return nil, err
			}
			columns = append(columns, col)
		}

		if len(columns) > 0 {
			var conditions []string
			for _, col := range columns {
				conditions = append(conditions, fmt.Sprintf("%s::text ILIKE $%d", col, argIndex))
				args = append(args, "%"+opts.Search+"%")
				argIndex++
			}
			whereClause = "WHERE " + strings.Join(conditions, " OR ")
		}
	}

	// Build ORDER BY clause
	orderBy := ""
	if opts.SortBy != "" {
		// Validate sort column exists
		colQuery := `SELECT column_name FROM information_schema.columns WHERE table_name = $1 AND table_schema = 'public' AND column_name = $2`
		var exists bool
		err := p.DB.QueryRowContext(ctx, colQuery, safeTableName, opts.SortBy).Scan(&exists)
		if err == nil && exists {
			dir := "ASC"
			if opts.SortDesc {
				dir = "DESC"
			}
			orderBy = fmt.Sprintf("ORDER BY %s %s", opts.SortBy, dir)
		}
	}

	// Count total rows (without limit/offset)
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM %s %s", safeTableName, whereClause)
	var totalRows int
	err := p.DB.QueryRowContext(ctx, countQuery, args...).Scan(&totalRows)
	if err != nil {
		return nil, err
	}

	// Build data query
	dataQuery := fmt.Sprintf("SELECT * FROM %s %s %s LIMIT $%d OFFSET $%d", safeTableName, whereClause, orderBy, argIndex, argIndex+1)
	args = append(args, limit, offset)

	rows, err := p.DB.QueryContext(ctx, dataQuery, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	columns, err := rows.Columns()
	if err != nil {
		return nil, err
	}

	var result [][]interface{}
	for rows.Next() {
		values := make([]interface{}, len(columns))
		valuePtrs := make([]interface{}, len(columns))
		for i := range columns {
			valuePtrs[i] = &values[i]
		}

		if err := rows.Scan(valuePtrs...); err != nil {
			return nil, err
		}

		rowValues := make([]interface{}, len(columns))
		for i, val := range values {
			if b, ok := val.([]byte); ok {
				rowValues[i] = string(b)
			} else {
				rowValues[i] = val
			}
		}
		result = append(result, rowValues)
	}

	return &QueryResult{
		Columns:     columns,
		Rows:        result,
		RowCount:    len(result),
		TotalRows:   totalRows,
		ExecutionMs: time.Since(start).Milliseconds(),
	}, nil
}

func (p *PostgresClient) GetTableStructure(ctx context.Context, tableName string, schema string) (*TableStructure, error) {
	if schema == "" {
		schema = "public"
	}
	safeTableName := sanitizeTableName(tableName)
	if safeTableName == "" {
		return nil, fmt.Errorf("nombre de tabla inválido")
	}

	structure := &TableStructure{Name: safeTableName}

	// 1. Get columns with detailed info
	columnsQuery := `
		SELECT 
			c.column_name,
			c.data_type,
			c.is_nullable = 'YES' as nullable,
			c.column_default,
			CASE WHEN pk.column_name IS NOT NULL THEN true ELSE false END as is_primary_key,
			CASE WHEN fk.column_name IS NOT NULL THEN true ELSE false END as is_foreign_key,
			fk.ref_table,
			fk.ref_column
		FROM information_schema.columns c
		LEFT JOIN (
			SELECT kcu.column_name
			FROM information_schema.table_constraints tc
			JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
			WHERE tc.table_name = $1 AND tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = $2
		) pk ON c.column_name = pk.column_name
		LEFT JOIN (
			SELECT kcu.column_name,
			       ccu.table_name as ref_table,
			       ccu.column_name as ref_column
			FROM information_schema.table_constraints tc
			JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
			JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
			WHERE tc.table_name = $1 AND tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = $2
		) fk ON c.column_name = fk.column_name
		WHERE c.table_name = $1 AND c.table_schema = $2
		ORDER BY c.ordinal_position;
	`

	rows, err := p.DB.QueryContext(ctx, columnsQuery, safeTableName, schema)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var col ColumnInfo
		var defaultVal sql.NullString
		var refTable, refColumn sql.NullString
		if err := rows.Scan(&col.Name, &col.Type, &col.Nullable, &defaultVal, &col.IsPrimaryKey, &col.IsForeignKey, &refTable, &refColumn); err != nil {
			return nil, err
		}
		if defaultVal.Valid {
			col.DefaultValue = defaultVal.String
		}
		if refTable.Valid {
			col.RefTable = refTable.String
		}
		if refColumn.Valid {
			col.RefColumn = refColumn.String
		}
		structure.Columns = append(structure.Columns, col)
	}

	// 2. Get indexes
	indexesQuery := `
		SELECT 
			i.relname as index_name,
			string_agg(a.attname, ',' ORDER BY a.attnum) as columns,
			ix.indisunique as unique,
			ix.indisprimary as primary
		FROM pg_class t
		JOIN pg_index ix ON t.oid = ix.indrelid
		JOIN pg_class i ON i.oid = ix.indexrelid
		JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
		WHERE t.relname = $1 AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = $2)
		GROUP BY i.relname, ix.indisunique, ix.indisprimary;
	`

	rows, err = p.DB.QueryContext(ctx, indexesQuery, safeTableName, schema)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var idx IndexInfo
		var columnsStr string
		if err := rows.Scan(&idx.Name, &columnsStr, &idx.Unique, &idx.Primary); err != nil {
			return nil, err
		}
		if columnsStr != "" {
			idx.Columns = strings.Split(columnsStr, ",")
		}
		structure.Indexes = append(structure.Indexes, idx)
	}

	// 3. Get foreign keys with actions
	fkQuery := `
		SELECT 
			tc.constraint_name,
			kcu.column_name,
			ccu.table_name as ref_table,
			ccu.column_name as ref_column,
			rc.update_rule as on_update,
			rc.delete_rule as on_delete
		FROM information_schema.table_constraints tc
		JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
		JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
		JOIN information_schema.referential_constraints rc ON tc.constraint_name = rc.constraint_name
		WHERE tc.table_name = $1 AND tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = $2;
	`

	rows, err = p.DB.QueryContext(ctx, fkQuery, safeTableName, schema)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var fk ForeignKeyInfo
		if err := rows.Scan(&fk.Name, &fk.Column, &fk.RefTable, &fk.RefColumn, &fk.OnUpdate, &fk.OnDelete); err != nil {
			return nil, err
		}
		structure.ForeignKeys = append(structure.ForeignKeys, fk)
	}

	return structure, nil
}

// sanitizeTableName valida que el nombre solo contenga caracteres alfanuméricos y underscore
func sanitizeTableName(name string) string {
	for _, r := range name {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_') {
			return ""
		}
	}
	return name
}

// ExportTable exports table data in the specified format
func (p *PostgresClient) ExportTable(ctx context.Context, opts ExportOptions) ([]byte, string, error) {
	safeTableName := sanitizeTableName(opts.TableName)
	if safeTableName == "" {
		return nil, "", fmt.Errorf("nombre de tabla inválido")
	}

	limit := opts.Limit
	if limit <= 0 || limit > 10000 {
		limit = 1000
	}
	offset := opts.Offset
	if offset < 0 {
		offset = 0
	}

	// Build WHERE clause for search (reuse logic from GetTableData)
	var whereClause string
	var args []interface{}
	argIndex := 1

	if opts.Search != "" {
		colQuery := `SELECT column_name FROM information_schema.columns WHERE table_name = $1 AND table_schema = 'public'`
		rows, err := p.DB.QueryContext(ctx, colQuery, safeTableName)
		if err != nil {
			return nil, "", err
		}
		defer rows.Close()

		var columns []string
		for rows.Next() {
			var col string
			if err := rows.Scan(&col); err != nil {
				return nil, "", err
			}
			columns = append(columns, col)
		}

		if len(columns) > 0 {
			var conditions []string
			for _, col := range columns {
				conditions = append(conditions, fmt.Sprintf("%s::text ILIKE $%d", col, argIndex))
				args = append(args, "%"+opts.Search+"%")
				argIndex++
			}
			whereClause = "WHERE " + strings.Join(conditions, " OR ")
		}
	}

	// Build ORDER BY clause
	orderBy := ""
	if opts.SortBy != "" {
		colQuery := `SELECT column_name FROM information_schema.columns WHERE table_name = $1 AND table_schema = 'public' AND column_name = $2`
		var exists bool
		err := p.DB.QueryRowContext(ctx, colQuery, safeTableName, opts.SortBy).Scan(&exists)
		if err == nil && exists {
			dir := "ASC"
			if opts.SortDesc {
				dir = "DESC"
			}
			orderBy = fmt.Sprintf("ORDER BY %s %s", opts.SortBy, dir)
		}
	}

	dataQuery := fmt.Sprintf("SELECT * FROM %s %s %s LIMIT $%d OFFSET $%d", safeTableName, whereClause, orderBy, argIndex, argIndex+1)
	args = append(args, limit, offset)

	rows, err := p.DB.QueryContext(ctx, dataQuery, args...)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()

	columns, err := rows.Columns()
	if err != nil {
		return nil, "", err
	}

	var result [][]interface{}
	for rows.Next() {
		values := make([]interface{}, len(columns))
		valuePtrs := make([]interface{}, len(columns))
		for i := range columns {
			valuePtrs[i] = &values[i]
		}

		if err := rows.Scan(valuePtrs...); err != nil {
			return nil, "", err
		}

		rowValues := make([]interface{}, len(columns))
		for i, val := range values {
			if b, ok := val.([]byte); ok {
				rowValues[i] = string(b)
			} else {
				rowValues[i] = val
			}
		}
		result = append(result, rowValues)
	}

	// Export based on format
	switch opts.Format {
	case "json":
		data, err := json.MarshalIndent(result, "", "  ")
		if err != nil {
			return nil, "", err
		}
		return data, safeTableName + ".json", nil
	case "csv":
		// Simple CSV export
		var sb strings.Builder
		// Header
		for i, col := range columns {
			if i > 0 {
				sb.WriteString(",")
			}
			sb.WriteString(col)
		}
		sb.WriteString("\n")
		// Rows
		for _, row := range result {
			for i, val := range row {
				if i > 0 {
					sb.WriteString(",")
				}
				if val != nil {
					sb.WriteString(fmt.Sprintf("%v", val))
				}
			}
			sb.WriteString("\n")
		}
		return []byte(sb.String()), safeTableName + ".csv", nil
	default:
		return nil, "", fmt.Errorf("formato no soportado: %s", opts.Format)
	}
}

// ImportTable imports data into a table (stub implementation)
func (p *PostgresClient) ImportTable(ctx context.Context, opts ImportOptions) (*ImportResult, error) {
	// TODO: Implement proper import logic
	return &ImportResult{
		RowsInserted: 0,
		RowsUpdated:  0,
		RowsSkipped:  0,
		Errors:       []string{"Import not yet implemented for PostgreSQL"},
	}, nil
}
