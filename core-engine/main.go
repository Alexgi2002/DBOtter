package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"time"

	api "dbotter.core/api"
)

func main() {
	// 1. Escuchar en un puerto aleatorio asignado por el OS (:0)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatalf("Error levantando listener: %v", err)
		return
	}

	port := listener.Addr().(*net.TCPAddr).Port

	fmt.Printf("DBOtter_PORT:%d\n", port)

	handler := api.Handler()

	server := &http.Server{
		Handler:      handler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
	}

	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Error en el servidor: %v", err)
	}
}
