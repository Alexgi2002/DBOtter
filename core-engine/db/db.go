package db

import "context"

// Table representa la estructura básica para la UI de SwiftUI
type Table struct {
	Name    string   `json:"name"`
	Columns []string `json:"columns,omitempty"`
}

type EngineType string

const (
	Postgres EngineType = "postgres"
	MySQL    EngineType = "mysql"
	SQLite   EngineType = "sqlite"
)

type ConnectRequest struct {
	Engine    EngineType `json:"engine"`
	Host      string     `json:"host"`
	Port      int        `json:"port"`
	Username  string     `json:"username"`
	Password  string     `json:"password"`
	SSLMode   string     `json:"ssl_mode,omitempty"`
	Database  string     `json:"database,omitempty"`  // Opcional: si vacío, conecta al motor sin BD específica
	FilePath  string     `json:"file_path,omitempty"` // Para SQLite

	// SSH Tunnel (opcional)
	SSHEnabled    bool   `json:"ssh_enabled,omitempty"`
	SSHHost       string `json:"ssh_host,omitempty"`
	SSHPort       int    `json:"ssh_port,omitempty"`
	SSHUsername   string `json:"ssh_username,omitempty"`
	SSHPassword   string `json:"ssh_password,omitempty"`
	SSHPrivateKey string `json:"ssh_private_key,omitempty"` // Contenido PEM
	SSHKeyPath    string `json:"ssh_key_path,omitempty"`    // Ruta al archivo
}

// DatabaseInfo representa una base de datos/esquema en el motor
type DatabaseInfo struct {
	Name        string `json:"name"`
	Owner       string `json:"owner,omitempty"`
	Encoding    string `json:"encoding,omitempty"`
	Collation   string `json:"collation,omitempty"`
	Description string `json:"description,omitempty"`
	IsDefault   bool   `json:"is_default,omitempty"`
}

// ColumnInfo represents detailed column information
type ColumnInfo struct {
	Name            string `json:"name"`
	Type            string `json:"type"`
	Nullable        bool   `json:"nullable"`
	DefaultValue    string `json:"default_value,omitempty"`
	IsPrimaryKey    bool   `json:"is_primary_key"`
	IsForeignKey    bool   `json:"is_foreign_key"`
	IsAutoIncrement bool   `json:"is_auto_increment"`
	RefTable        string `json:"ref_table,omitempty"`
	RefColumn       string `json:"ref_column,omitempty"`
}

// TableStructure represents complete table metadata
type TableStructure struct {
	Name        string       `json:"name"`
	Columns     []ColumnInfo `json:"columns"`
	Indexes     []IndexInfo  `json:"indexes"`
	ForeignKeys []ForeignKeyInfo `json:"foreign_keys"`
}

type IndexInfo struct {
	Name    string   `json:"name"`
	Columns []string `json:"columns"`
	Unique  bool     `json:"unique"`
	Primary bool     `json:"primary"`
}

type ForeignKeyInfo struct {
	Name           string `json:"name"`
	Column         string `json:"column"`
	RefTable       string `json:"ref_table"`
	RefColumn      string `json:"ref_column"`
	OnUpdate       string `json:"on_update"`
	OnDelete       string `json:"on_delete"`
}

// TableDataOptions para filtrado y paginación
type TableDataOptions struct {
	TableName string
	Limit     int
	Offset    int
	Search    string        // Texto a buscar en todas las columnas
	SortBy    string        // Columna para ordenar
	SortDesc  bool          // Orden descendente
}

// ExportOptions para exportación profesional
type ExportOptions struct {
	TableName  string   `json:"table_name"`
	Format     string   `json:"format"`               // "csv", "xlsx", "json", "sql_insert", "sql_update"
	Columns    []string `json:"columns,omitempty"`     // Columnas específicas (vacío = todas)
	Limit      int      `json:"limit,omitempty"`       // 0 = sin límite
	Offset     int      `json:"offset,omitempty"`
	Search     string   `json:"search,omitempty"`      // Filtro de búsqueda
	SortBy     string   `json:"sort_by,omitempty"`
	SortDesc   bool     `json:"sort_desc,omitempty"`
	Where      string   `json:"where,omitempty"`       // WHERE clause adicional
	
	// CSV options
	Delimiter  string `json:"delimiter,omitempty"`     // ",", ";", "\t", "|"
	QuoteChar  string `json:"quote_char,omitempty"`    // "\"", "'", ""
	Encoding   string `json:"encoding,omitempty"`      // "utf-8", "utf-8-bom", "utf-16", "latin1"
	LineEnding string `json:"line_ending,omitempty"`   // "\n", "\r\n"
	
	// Excel options
	SheetName   string `json:"sheet_name,omitempty"`   // Nombre de la hoja
	FreezePanes bool   `json:"freeze_panes,omitempty"` // Congelar primera fila
	AutoWidth   bool   `json:"auto_width,omitempty"`   // Ajustar ancho de columnas
	HeaderBold  bool   `json:"header_bold,omitempty"`  // Negrita en encabezados
	
	// Metadata
	IncludeHeader    bool `json:"include_header,omitempty"`     // Incluir encabezados (default: true)
	IncludeTypes     bool `json:"include_types,omitempty"`      // Incluir tipos de columna
	IncludeTimestamp bool `json:"include_timestamp,omitempty"`  // Incluir fecha de exportación
	IncludeQuery     bool `json:"include_query,omitempty"`      // Incluir SQL usado
	IncludeStats     bool `json:"include_stats,omitempty"`      // Incluir estadísticas (total rows, execution time)
}

// ImportOptions para importación
type ImportOptions struct {
	TableName  string
	Format     string        // "csv", "json"
	Data       string        // Contenido del archivo
	Truncate   bool          // Truncar tabla antes
	SkipHeader bool          // Saltar primera fila (CSV)
}

// QueryResult con metadata adicional
type QueryResult struct {
	Columns     []string        `json:"columns,omitempty"`
	Rows        [][]interface{} `json:"rows,omitempty"`
	RowCount    int             `json:"row_count,omitempty"`
	TotalRows   int             `json:"total_rows,omitempty"`
	ExecutionMs int64           `json:"execution_ms,omitempty"`
	
	// Para queries que no son SELECT (INSERT, UPDATE, DELETE, DDL)
	RowsAffected int64  `json:"rows_affected,omitempty"`
	LastInsertID  int64  `json:"last_insert_id,omitempty"`
	Message       string `json:"message,omitempty"`
	IsSelect      bool   `json:"is_select"`
}

// DatabaseClient es la capa abstracta. DBOtter solo hablará con esta interfaz.
type DatabaseClient interface {
	Connect(ctx context.Context, config ConnectRequest) error
	Disconnect() error
	GetDatabases(ctx context.Context) ([]DatabaseInfo, error)
	GetTables(ctx context.Context, schema string) ([]Table, error)
	ExecuteQuery(ctx context.Context, query string) (*QueryResult, error)
	GetTableData(ctx context.Context, opts TableDataOptions) (*QueryResult, error)
	GetTableStructure(ctx context.Context, tableName string, schema string) (*TableStructure, error)
	ExportTable(ctx context.Context, opts ExportOptions) ([]byte, string, error) // data, filename, error
	ImportTable(ctx context.Context, opts ImportOptions) (*ImportResult, error)
}

type ImportResult struct {
	RowsInserted int    `json:"rows_inserted"`
	RowsUpdated  int    `json:"rows_updated"`
	RowsSkipped  int    `json:"rows_skipped"`
	Errors       []string `json:"errors,omitempty"`
}