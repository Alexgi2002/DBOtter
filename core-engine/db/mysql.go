package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

type MySQLClient struct {
	DB *sql.DB
}

func NewMySQLClient(db *sql.DB) DatabaseClient {
	return &MySQLClient{DB: db}
}

func (m *MySQLClient) Connect(ctx context.Context, config ConnectRequest) error {
	// MySQL DSN: user:password@tcp(host:port)/dbname
	// Si database está vacío, conecta sin dbname para listar todas
	dbName := config.Database
	if dbName == "" {
		dbName = ""
	}

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?charset=utf8mb4&parseTime=True&loc=Local",
		config.Username, config.Password, config.Host, config.Port, dbName)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return fmt.Errorf("error abriendo MySQL: %w", err)
	}

	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("error conectando a MySQL: %w", err)
	}

	m.DB = db
	return nil
}

func (m *MySQLClient) Disconnect() error {
	if m.DB != nil {
		return m.DB.Close()
	}
	return nil
}

// GetDatabases — lista todas las bases de datos en el servidor
func (m *MySQLClient) GetDatabases(ctx context.Context) ([]DatabaseInfo, error) {
	query := `
		SELECT SCHEMA_NAME, DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME
		FROM information_schema.SCHEMATA
		WHERE SCHEMA_NAME NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')
		ORDER BY SCHEMA_NAME;
	`
	rows, err := m.DB.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var databases []DatabaseInfo
	for rows.Next() {
		var db DatabaseInfo
		var charset, collation sql.NullString
		if err := rows.Scan(&db.Name, &charset, &collation); err != nil {
			return nil, err
		}
		if charset.Valid {
			db.Encoding = charset.String
		}
		if collation.Valid {
			db.Collation = collation.String
		}
		databases = append(databases, db)
	}
	return databases, nil
}

// GetTables — lista tablas de la BD actual
func (m *MySQLClient) GetTables(ctx context.Context, schema string) ([]Table, error) {
	query := `SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME`
	rows, err := m.DB.QueryContext(ctx, query)
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

func (m *MySQLClient) ExecuteQuery(ctx context.Context, query string) (*QueryResult, error) {
	start := time.Now()

	// Detectar si es SELECT o SHOW (queries que retornan datos)
	upperQuery := strings.TrimSpace(strings.ToUpper(query))
	isSelect := strings.HasPrefix(upperQuery, "SELECT") ||
		strings.HasPrefix(upperQuery, "SHOW") ||
		strings.HasPrefix(upperQuery, "WITH") ||
		strings.HasPrefix(upperQuery, "EXPLAIN") ||
		strings.HasPrefix(upperQuery, "DESCRIBE") ||
		strings.HasPrefix(upperQuery, "DESC ")

	if isSelect {
		rows, err := m.DB.QueryContext(ctx, query)
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
				switch v := val.(type) {
				case []byte:
					rowValues[i] = string(v)
				case time.Time:
					rowValues[i] = v.Format(time.RFC3339)
				default:
					rowValues[i] = v
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
	result, err := m.DB.ExecContext(ctx, query)
	if err != nil {
		return nil, err
	}

	rowsAffected, _ := result.RowsAffected()
	lastInsertID, _ := result.LastInsertId()

	return &QueryResult{
		IsSelect:     false,
		RowsAffected: rowsAffected,
		LastInsertID: lastInsertID,
		Message:      fmt.Sprintf("Query ejecutada. %d filas afectadas.", rowsAffected),
		ExecutionMs:  time.Since(start).Milliseconds(),
	}, nil
}

func (m *MySQLClient) GetTableData(ctx context.Context, opts TableDataOptions) (*QueryResult, error) {
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

	// Obtener columnas para búsqueda
	var whereClause string
	var args []interface{}

	if opts.Search != "" {
		colQuery := `SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?`
		rows, err := m.DB.QueryContext(ctx, colQuery, safeTableName)
		if err == nil {
			defer rows.Close()

			var columns []string
			for rows.Next() {
				var col string
				if err := rows.Scan(&col); err != nil {
					continue
				}
				columns = append(columns, col)
			}

			if len(columns) > 0 {
				var conditions []string
				for _, col := range columns {
					conditions = append(conditions, fmt.Sprintf("CAST(`%s` AS CHAR) LIKE ?", col))
					args = append(args, "%"+opts.Search+"%")
				}
				whereClause = "WHERE " + strings.Join(conditions, " OR ")
			}
		}
	}

	// ORDER BY
	orderBy := ""
	if opts.SortBy != "" {
		dir := "ASC"
		if opts.SortDesc {
			dir = "DESC"
		}
		orderBy = fmt.Sprintf("ORDER BY `%s` %s", opts.SortBy, dir)
	}

	// COUNT total
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM `%s` %s", safeTableName, whereClause)
	var totalRows int
	err := m.DB.QueryRowContext(ctx, countQuery, args...).Scan(&totalRows)
	if err != nil {
		return nil, err
	}

	// Data query — MySQL usa ? para placeholders
	dataQuery := fmt.Sprintf("SELECT * FROM `%s` %s %s LIMIT ? OFFSET ?", safeTableName, whereClause, orderBy)
	args = append(args, limit, offset)

	rows, err := m.DB.QueryContext(ctx, dataQuery, args...)
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
			switch v := val.(type) {
			case []byte:
				rowValues[i] = string(v)
			case time.Time:
				rowValues[i] = v.Format(time.RFC3339)
			default:
				rowValues[i] = v
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

func (m *MySQLClient) GetTableStructure(ctx context.Context, tableName string, schema string) (*TableStructure, error) {
	if schema == "" {
		schema = "public"
	}
	safeTableName := sanitizeTableName(tableName)
	if safeTableName == "" {
		return nil, fmt.Errorf("nombre de tabla inválido")
	}

	structure := &TableStructure{Name: safeTableName}

	// 1. Columnas
	columnsQuery := `
		SELECT 
			COLUMN_NAME,
			COLUMN_TYPE,
			IS_NULLABLE = 'YES' as nullable,
			COLUMN_DEFAULT,
			COLUMN_KEY = 'PRI' as is_primary_key,
			COLUMN_KEY = 'FK' as is_foreign_key,
			EXTRA LIKE '%auto_increment%' as is_auto_increment
		FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
		ORDER BY ORDINAL_POSITION;
	`
	rows, err := m.DB.QueryContext(ctx, columnsQuery, schema, safeTableName)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var col ColumnInfo
		var defaultVal sql.NullString
		if err := rows.Scan(&col.Name, &col.Type, &col.Nullable, &defaultVal, &col.IsPrimaryKey, &col.IsForeignKey, &col.IsAutoIncrement); err != nil {
			return nil, err
		}
		if defaultVal.Valid {
			col.DefaultValue = defaultVal.String
		}
		structure.Columns = append(structure.Columns, col)
	}

	// 2. Índices
	indexesQuery := `
		SELECT 
			INDEX_NAME,
			GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) as columns,
			NON_UNIQUE = 0 as unique_idx,
			INDEX_NAME = 'PRIMARY' as primary_idx
		FROM information_schema.STATISTICS
		WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
		GROUP BY INDEX_NAME, NON_UNIQUE
		ORDER BY INDEX_NAME;
	`
	idxRows, err := m.DB.QueryContext(ctx, indexesQuery, schema, safeTableName)
	if err == nil {
		defer idxRows.Close()

		for idxRows.Next() {
			var idx IndexInfo
			var columnsStr string
			if err := idxRows.Scan(&idx.Name, &columnsStr, &idx.Unique, &idx.Primary); err != nil {
				continue
			}
			idx.Columns = strings.Split(columnsStr, ",")
			structure.Indexes = append(structure.Indexes, idx)
		}
	}

	// 3. Foreign keys
	fkQuery := `
		SELECT 
			tc.CONSTRAINT_NAME,
			kcu.COLUMN_NAME,
			ccu.TABLE_NAME as ref_table,
			ccu.COLUMN_NAME as ref_column,
			rc.UPDATE_RULE as on_update,
			rc.DELETE_RULE as on_delete
		FROM information_schema.TABLE_CONSTRAINTS tc
		JOIN information_schema.KEY_COLUMN_USAGE kcu ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
		JOIN information_schema.CONSTRAINT_COLUMN_USAGE ccu ON tc.CONSTRAINT_NAME = ccu.CONSTRAINT_NAME
		JOIN information_schema.REFERENTIAL_CONSTRAINTS rc ON tc.CONSTRAINT_NAME = rc.CONSTRAINT_NAME
		WHERE tc.TABLE_SCHEMA = ? AND tc.TABLE_NAME = ? AND tc.CONSTRAINT_TYPE = 'FOREIGN KEY';
	`
	fkRows, err := m.DB.QueryContext(ctx, fkQuery, schema, safeTableName)
	if err == nil {
		defer fkRows.Close()

		for fkRows.Next() {
			var fk ForeignKeyInfo
			if err := fkRows.Scan(&fk.Name, &fk.Column, &fk.RefTable, &fk.RefColumn, &fk.OnUpdate, &fk.OnDelete); err != nil {
				continue
			}
			structure.ForeignKeys = append(structure.ForeignKeys, fk)
		}
	}

	return structure, nil
}

func (m *MySQLClient) ExportTable(ctx context.Context, opts ExportOptions) ([]byte, string, error) {
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

	// WHERE clause for search
	var whereClause string
	var args []interface{}

	if opts.Search != "" {
		colQuery := `SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?`
		rows, err := m.DB.QueryContext(ctx, colQuery, safeTableName)
		if err == nil {
			defer rows.Close()
			var columns []string
			for rows.Next() {
				var col string
				if err := rows.Scan(&col); err != nil {
					continue
				}
				columns = append(columns, col)
			}
			if len(columns) > 0 {
				var conditions []string
				for _, col := range columns {
					conditions = append(conditions, fmt.Sprintf("CAST(`%s` AS CHAR) LIKE ?", col))
					args = append(args, "%"+opts.Search+"%")
				}
				whereClause = "WHERE " + strings.Join(conditions, " OR ")
			}
		}
	}

	// ORDER BY
	orderBy := ""
	if opts.SortBy != "" {
		dir := "ASC"
		if opts.SortDesc {
			dir = "DESC"
		}
		orderBy = fmt.Sprintf("ORDER BY `%s` %s", opts.SortBy, dir)
	}

	dataQuery := fmt.Sprintf("SELECT * FROM `%s` %s %s LIMIT ? OFFSET ?", safeTableName, whereClause, orderBy)
	args = append(args, limit, offset)

	rows, err := m.DB.QueryContext(ctx, dataQuery, args...)
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
			switch v := val.(type) {
			case []byte:
				rowValues[i] = string(v)
			case time.Time:
				rowValues[i] = v.Format(time.RFC3339)
			default:
				rowValues[i] = v
			}
		}
		result = append(result, rowValues)
	}

	switch opts.Format {
	case "json":
		data, err := json.MarshalIndent(result, "", "  ")
		if err != nil {
			return nil, "", err
		}
		return data, safeTableName + ".json", nil
	case "csv":
		var sb strings.Builder
		for i, col := range columns {
			if i > 0 {
				sb.WriteString(",")
			}
			sb.WriteString(col)
		}
		sb.WriteString("\n")
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

func (m *MySQLClient) ImportTable(ctx context.Context, opts ImportOptions) (*ImportResult, error) {
	return &ImportResult{
		Errors: []string{"Import not yet implemented for MySQL"},
	}, nil
}
