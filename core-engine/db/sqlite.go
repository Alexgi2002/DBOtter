package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite" // Driver SQLite puro Go (sin CGO)
)

type SQLiteClient struct {
	DB       *sql.DB
	FilePath string
}

func NewSQLiteClient(db *sql.DB, filePath string) DatabaseClient {
	return &SQLiteClient{DB: db, FilePath: filePath}
}

func (s *SQLiteClient) Connect(ctx context.Context, config ConnectRequest) error {
	filePath := config.FilePath
	if filePath == "" {
		return fmt.Errorf("file_path es requerido para SQLite")
	}

	// WAL mode + foreign keys + busy timeout
	dsn := filePath + "?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(ON)"

	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return fmt.Errorf("error abriendo SQLite: %w", err)
	}

	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("error conectando a SQLite: %w", err)
	}

	s.DB = db
	s.FilePath = filePath
	return nil
}

func (s *SQLiteClient) Disconnect() error {
	if s.DB != nil {
		return s.DB.Close()
	}
	return nil
}

// GetDatabases — SQLite no tiene múltiples databases, retorna una sola entrada
func (s *SQLiteClient) GetDatabases(ctx context.Context) ([]DatabaseInfo, error) {
	return []DatabaseInfo{
		{
			Name:      s.FilePath,
			IsDefault: true,
		},
	}, nil
}

// GetTables — usa sqlite_master
func (s *SQLiteClient) GetTables(ctx context.Context, schema string) ([]Table, error) {
	query := `
		SELECT name FROM sqlite_master
		WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
		ORDER BY name;
	`
	rows, err := s.DB.QueryContext(ctx, query)
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

func (s *SQLiteClient) ExecuteQuery(ctx context.Context, query string) (*QueryResult, error) {
	start := time.Now()

	// Detectar si es SELECT o PRAGMA (queries que retornan datos)
	upperQuery := strings.TrimSpace(strings.ToUpper(query))
	isSelect := strings.HasPrefix(upperQuery, "SELECT") ||
		strings.HasPrefix(upperQuery, "PRAGMA") ||
		strings.HasPrefix(upperQuery, "EXPLAIN") ||
		strings.HasPrefix(upperQuery, "WITH")

	if isSelect {
		rows, err := s.DB.QueryContext(ctx, query)
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
	result, err := s.DB.ExecContext(ctx, query)
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

func (s *SQLiteClient) GetTableData(ctx context.Context, opts TableDataOptions) (*QueryResult, error) {
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
		colQuery := `PRAGMA table_info(?)`
		rows, err := s.DB.QueryContext(ctx, colQuery, safeTableName)
		if err == nil {
			defer rows.Close()

			var columns []string
			for rows.Next() {
				var cid int
				var name, colType string
				var notNull int
				var defaultVal sql.NullString
				var pk int
				if err := rows.Scan(&cid, &name, &colType, &notNull, &defaultVal, &pk); err != nil {
					continue
				}
				columns = append(columns, name)
			}

			if len(columns) > 0 {
				var conditions []string
				for _, col := range columns {
					conditions = append(conditions, fmt.Sprintf("CAST([%s] AS TEXT) LIKE ?", col))
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
		orderBy = fmt.Sprintf("ORDER BY [%s] %s", opts.SortBy, dir)
	}

	// COUNT total
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM [%s] %s", safeTableName, whereClause)
	var totalRows int
	err := s.DB.QueryRowContext(ctx, countQuery, args...).Scan(&totalRows)
	if err != nil {
		return nil, err
	}

	// Data query — SQLite usa ? para placeholders
	dataQuery := fmt.Sprintf("SELECT * FROM [%s] %s %s LIMIT ? OFFSET ?", safeTableName, whereClause, orderBy)
	args = append(args, limit, offset)

	rows, err := s.DB.QueryContext(ctx, dataQuery, args...)
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

func (s *SQLiteClient) GetTableStructure(ctx context.Context, tableName string, schema string) (*TableStructure, error) {
	if schema == "" {
		schema = "main" // SQLite uses "main" for the primary database
	}
	safeTableName := sanitizeTableName(tableName)
	if safeTableName == "" {
		return nil, fmt.Errorf("nombre de tabla inválido")
	}

	structure := &TableStructure{Name: safeTableName}

	// 1. Columnas via PRAGMA table_info
	colQuery := fmt.Sprintf("PRAGMA %s.table_info([%s])", schema, safeTableName)
	rows, err := s.DB.QueryContext(ctx, colQuery)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var col ColumnInfo
		var cid int
		var notNull int
		var defaultVal sql.NullString
		var pk int

		if err := rows.Scan(&cid, &col.Name, &col.Type, &notNull, &defaultVal, &pk); err != nil {
			return nil, err
		}
		col.Nullable = notNull == 0
		col.IsPrimaryKey = pk > 0
		if defaultVal.Valid {
			col.DefaultValue = defaultVal.String
		}
		col.IsAutoIncrement = strings.Contains(strings.ToUpper(col.Type), "INTEGER") && pk > 0
		structure.Columns = append(structure.Columns, col)
	}

	// 2. Foreign keys via PRAGMA foreign_key_list
	fkQuery := fmt.Sprintf("PRAGMA %s.foreign_key_list([%s])", schema, safeTableName)
	fkRows, err := s.DB.QueryContext(ctx, fkQuery)
	if err == nil {
		defer fkRows.Close()

		fkMap := make(map[string]*ForeignKeyInfo)
		for fkRows.Next() {
			var id, seq int
			var table, from, to, onUpdate, onDelete string
			if err := fkRows.Scan(&id, &seq, &table, &from, &to, &onUpdate, &onDelete); err != nil {
				continue
			}

			fkName := fmt.Sprintf("fk_%s_%s", safeTableName, from)
			if existing, ok := fkMap[fkName]; ok {
				existing.RefTable = table
			} else {
				fkMap[fkName] = &ForeignKeyInfo{
					Name:      fkName,
					Column:    from,
					RefTable:  table,
					RefColumn: to,
					OnUpdate:  onUpdate,
					OnDelete:  onDelete,
				}
			}

			// Marcar columna como foreign key
			for i := range structure.Columns {
				if structure.Columns[i].Name == from {
					structure.Columns[i].IsForeignKey = true
					structure.Columns[i].RefTable = table
					structure.Columns[i].RefColumn = to
					break
				}
			}
		}
		for _, fk := range fkMap {
			structure.ForeignKeys = append(structure.ForeignKeys, *fk)
		}
	}

	// 3. Índices via PRAGMA index_list + PRAGMA index_info
	idxListQuery := fmt.Sprintf("PRAGMA %s.index_list([%s])", schema, safeTableName)
	idxRows, err := s.DB.QueryContext(ctx, idxListQuery)
	if err == nil {
		defer idxRows.Close()

		for idxRows.Next() {
			var seq int
			var idxName string
			var unique int
			if err := idxRows.Scan(&seq, &idxName, &unique); err != nil {
				continue
			}

			idxInfo := IndexInfo{
				Name:   idxName,
				Unique: unique == 1,
			}

			// Obtener columnas del índice
			idxInfoQuery := fmt.Sprintf("PRAGMA %s.index_info([%s])", schema, idxName)
			idxInfoRows, err := s.DB.QueryContext(ctx, idxInfoQuery)
			if err == nil {
				for idxInfoRows.Next() {
					var seqNo, cid int
					var colName string
					if err := idxInfoRows.Scan(&seqNo, &cid, &colName); err != nil {
						continue
					}
					idxInfo.Columns = append(idxInfo.Columns, colName)
					// Detectar primary key por nombre
					if strings.Contains(strings.ToLower(idxName), "primary") || strings.Contains(strings.ToLower(idxName), "pk_") {
						idxInfo.Primary = true
					}
				}
				idxInfoRows.Close()
			}

			structure.Indexes = append(structure.Indexes, idxInfo)
		}
	}

	return structure, nil
}

func (s *SQLiteClient) ExportTable(ctx context.Context, opts ExportOptions) ([]byte, string, error) {
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
		colQuery := fmt.Sprintf("PRAGMA table_info([%s])", safeTableName)
		rows, err := s.DB.QueryContext(ctx, colQuery, safeTableName)
		if err == nil {
			defer rows.Close()
			var columns []string
			for rows.Next() {
				var cid int
				var name, colType string
				var notNull int
				var defaultVal sql.NullString
				var pk int
				if err := rows.Scan(&cid, &name, &colType, &notNull, &defaultVal, &pk); err != nil {
					continue
				}
				columns = append(columns, name)
			}
			if len(columns) > 0 {
				var conditions []string
				for _, col := range columns {
					conditions = append(conditions, fmt.Sprintf("CAST([%s] AS TEXT) LIKE ?", col))
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
		orderBy = fmt.Sprintf("ORDER BY [%s] %s", opts.SortBy, dir)
	}

	dataQuery := fmt.Sprintf("SELECT * FROM [%s] %s %s LIMIT ? OFFSET ?", safeTableName, whereClause, orderBy)
	args = append(args, limit, offset)

	rows, err := s.DB.QueryContext(ctx, dataQuery, args...)
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

func (s *SQLiteClient) ImportTable(ctx context.Context, opts ImportOptions) (*ImportResult, error) {
	return &ImportResult{
		Errors: []string{"Import not yet implemented for SQLite"},
	}, nil
}
