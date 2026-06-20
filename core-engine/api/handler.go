package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"dbotter.core/db"
)

var currentDB db.DatabaseClient
var currentTunnel *db.SSHTunnel

func Handler() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /connect", handleConnect)
	mux.HandleFunc("POST /disconnect", handleDisconnect)
	mux.HandleFunc("GET /databases", handleGetDatabases)
	mux.HandleFunc("GET /tables", handleGetTables)
	mux.HandleFunc("GET /table-data", handleGetTableData)
	mux.HandleFunc("GET /table-structure", handleGetTableStructure)
	mux.HandleFunc("GET /export", handleExport)
	mux.HandleFunc("POST /export", handleExport)
	mux.HandleFunc("POST /query", handleQuery)

	return mux
}

func handleConnect(w http.ResponseWriter, r *http.Request) {
	var req db.ConnectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	sshEnabled := req.SSHEnabled || req.SSHHost != "" || req.SSHUsername != "" || req.SSHPassword != "" || req.SSHPrivateKey != "" || req.SSHKeyPath != ""
	fmt.Printf("[connect] received params: engine=%s host=%q port=%d database=%v sshEnabled=%v sshHost=%q sshPort=%d\n", req.Engine, req.Host, req.Port, req.Database, sshEnabled, req.SSHHost, req.SSHPort)

	// Cerrar túnel anterior si existía
	if currentTunnel != nil {
		currentTunnel.Close()
		currentTunnel = nil
	}

	// Levantar túnel SSH si está habilitado
	if sshEnabled {
		remoteHost := req.Host
		remotePort := req.Port
		fmt.Printf("[connect] SSH enabled: remote db host=%q port=%d ssh host=%q ssh port=%d\n", remoteHost, remotePort, req.SSHHost, req.SSHPort)
		tunnel, err := db.NewSSHTunnel(db.SSHConfig{
			Host:       req.SSHHost,
			Port:       req.SSHPort,
			Username:   req.SSHUsername,
			Password:   req.SSHPassword,
			PrivateKey: req.SSHPrivateKey,
			KeyPath:    req.SSHKeyPath,
			DBHost:     remoteHost,
			DBPort:     remotePort,
		})
		if err != nil {
			http.Error(w, fmt.Sprintf("Error SSH tunnel: %v", err), http.StatusBadRequest)
			return
		}
		currentTunnel = tunnel
		// Redirigir la conexión al puerto local del túnel
		req.Host = "127.0.0.1"
		req.Port = tunnel.LocalPort
		fmt.Printf("[connect] SSH tunnel created: local=%s:%d remote=%s:%d\n", req.Host, req.Port, remoteHost, remotePort)
	}

	switch req.Engine {
	case db.Postgres:
		currentDB = &db.PostgresClient{}
	case db.MySQL:
		currentDB = &db.MySQLClient{}
	case db.SQLite:
		currentDB = &db.SQLiteClient{}
	default:
		http.Error(w, fmt.Sprintf("Engine no soportado: %s", req.Engine), http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	fmt.Printf("[connect] final target: engine=%s host=%s port=%d db=%q sslmode=%s ssh=%v\n", req.Engine, req.Host, req.Port, req.Database, req.SSLMode, req.SSHEnabled)
	if err := currentDB.Connect(ctx, req); err != nil {
		// Si falla la conexión a la BD, cerrar el túnel SSH
		if currentTunnel != nil {
			currentTunnel.Close()
			currentTunnel = nil
		}
		http.Error(w, fmt.Sprintf("Error de conexión: %v", err), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "connected"})
}

func handleDisconnect(w http.ResponseWriter, r *http.Request) {
	if currentDB != nil {
		currentDB.Disconnect()
		currentDB = nil
	}
	if currentTunnel != nil {
		currentTunnel.Close()
		currentTunnel = nil
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "disconnected"})
}

func handleGetDatabases(w http.ResponseWriter, r *http.Request) {
	if currentDB == nil {
		http.Error(w, "No hay una base de datos conectada", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbs, err := currentDB.GetDatabases(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(dbs)
}

func handleGetTables(w http.ResponseWriter, r *http.Request) {
	if currentDB == nil {
		http.Error(w, "No hay una base de datos conectada", http.StatusBadRequest)
		return
	}

	schema := r.URL.Query().Get("schema")
	if schema == "" {
		schema = "public"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	tables, err := currentDB.GetTables(ctx, schema)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tables)
}

func handleGetTableData(w http.ResponseWriter, r *http.Request) {
	if currentDB == nil {
		http.Error(w, "No hay una base de datos conectada", http.StatusBadRequest)
		return
	}

	tableName := r.URL.Query().Get("table")
	if tableName == "" {
		http.Error(w, "Parámetro 'table' requerido", http.StatusBadRequest)
		return
	}

	limit := 100
	offset := 0
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 1000 {
			limit = parsed
		}
	}
	if o := r.URL.Query().Get("offset"); o != "" {
		if parsed, err := strconv.Atoi(o); err == nil && parsed >= 0 {
			offset = parsed
		}
	}

	search := r.URL.Query().Get("search")
	sortBy := r.URL.Query().Get("sort_by")
	sortDesc := r.URL.Query().Get("sort_desc") == "true"

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	opts := db.TableDataOptions{
		TableName: tableName,
		Limit:     limit,
		Offset:    offset,
		Search:    search,
		SortBy:    sortBy,
		SortDesc:  sortDesc,
	}

	data, err := currentDB.GetTableData(ctx, opts)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}

func handleGetTableStructure(w http.ResponseWriter, r *http.Request) {
	if currentDB == nil {
		writeError(w, http.StatusBadRequest, "No hay una base de datos conectada")
		return
	}

	tableName := r.URL.Query().Get("table")
	if tableName == "" {
		writeError(w, http.StatusBadRequest, "Parámetro 'table' requerido")
		return
	}

	schema := r.URL.Query().Get("schema")
	if schema == "" {
		schema = "public"
	}

	fmt.Printf("[table-structure] request table=%q schema=%q\n", tableName, schema)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	structure, err := currentDB.GetTableStructure(ctx, tableName, schema)
	if err != nil {
		fmt.Printf("[table-structure] error table=%q schema=%q err=%v\n", tableName, schema, err)
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("Error al obtener la estructura de la tabla %q: %v", tableName, err))
		return
	}

	body, marshalErr := json.Marshal(structure)
	if marshalErr != nil {
		fmt.Printf("[table-structure] marshal error table=%q schema=%q err=%v\n", tableName, schema, marshalErr)
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("Error serializando estructura de la tabla %q: %v", tableName, marshalErr))
		return
	}

	fmt.Printf("[table-structure] response table=%q schema=%q body=%s\n", tableName, schema, string(body))

	w.Header().Set("Content-Type", "application/json")
	w.Write(body)
}

func handleExport(w http.ResponseWriter, r *http.Request) {
	if currentDB == nil {
		http.Error(w, "No hay una base de datos conectada", http.StatusBadRequest)
		return
	}

	// Parsear opciones desde query params (GET) o body (POST)
	var opts db.ExportOptions

	if r.Method == "POST" {
		if err := json.NewDecoder(r.Body).Decode(&opts); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
	} else {
		// GET params
		opts.TableName = r.URL.Query().Get("table")
		opts.Format = r.URL.Query().Get("format")
		opts.Search = r.URL.Query().Get("search")
		opts.SortBy = r.URL.Query().Get("sort_by")
		opts.SortDesc = r.URL.Query().Get("sort_desc") == "true"
		opts.Where = r.URL.Query().Get("where")
		opts.Delimiter = r.URL.Query().Get("delimiter")
		opts.QuoteChar = r.URL.Query().Get("quote_char")
		opts.Encoding = r.URL.Query().Get("encoding")
		opts.SheetName = r.URL.Query().Get("sheet_name")
		opts.IncludeHeader = r.URL.Query().Get("include_header") != "false"
		opts.IncludeTypes = r.URL.Query().Get("include_types") == "true"
		opts.IncludeTimestamp = r.URL.Query().Get("include_timestamp") == "true"
		opts.IncludeQuery = r.URL.Query().Get("include_query") == "true"
		opts.IncludeStats = r.URL.Query().Get("include_stats") == "true"
		opts.FreezePanes = r.URL.Query().Get("freeze_panes") == "true"
		opts.AutoWidth = r.URL.Query().Get("auto_width") == "true"
		opts.HeaderBold = r.URL.Query().Get("header_bold") == "true"

		if l := r.URL.Query().Get("limit"); l != "" {
			if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 {
				opts.Limit = parsed
			}
		}
		if o := r.URL.Query().Get("offset"); o != "" {
			if parsed, err := strconv.Atoi(o); err == nil && parsed >= 0 {
				opts.Offset = parsed
			}
		}
	}

	// Validar parámetros requeridos
	if opts.TableName == "" {
		http.Error(w, "Parámetro 'table' requerido", http.StatusBadRequest)
		return
	}
	if opts.Format == "" {
		opts.Format = "csv"
	}

	// Preparar response headers según formato
	contentType := "text/csv"
	fileExt := ".csv"
	switch opts.Format {
	case "xlsx":
		contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
		fileExt = ".xlsx"
	case "json":
		contentType = "application/json"
		fileExt = ".json"
	case "sql_insert", "sql_update":
		contentType = "text/plain"
		fileExt = ".sql"
	}

	filename := fmt.Sprintf("%s%s", opts.TableName, fileExt)
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))

	// Ejecutar exportación
	exportMgr := db.NewExportManager(currentDB)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	result, err := exportMgr.Export(ctx, w, opts)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Log del resultado
	_ = result
}

// QueryRequest represents a raw SQL query request
type QueryRequest struct {
	Query string `json:"query"`
}

func handleQuery(w http.ResponseWriter, r *http.Request) {
	if currentDB == nil {
		http.Error(w, "No hay una base de datos conectada", http.StatusBadRequest)
		return
	}

	var req QueryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if req.Query == "" {
		http.Error(w, "Parámetro 'query' requerido", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	result, err := currentDB.ExecuteQuery(ctx, req.Query)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error ejecutando query: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}
