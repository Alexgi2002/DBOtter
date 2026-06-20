package db

import (
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/crypto/ssh"
)

// SSHTunnel mantiene el túnel activo y el listener local
type SSHTunnel struct {
	client   *ssh.Client
	listener net.Listener
	LocalPort int
}

// SSHConfig contiene los parámetros para establecer el túnel
type SSHConfig struct {
	Host       string // SSH server host
	Port       int    // SSH server port (default 22)
	Username   string // SSH username
	Password   string // SSH password (opcional si se usa key)
	PrivateKey string // Contenido de la clave privada PEM (opcional)
	KeyPath    string // Ruta al archivo de clave privada (opcional)
	DBHost     string // Host de la BD visto desde el servidor SSH
	DBPort     int    // Puerto de la BD visto desde el servidor SSH
}

// NewSSHTunnel establece la conexión SSH y abre un listener local en un puerto aleatorio.
// El caller debe llamar Close() cuando termine.
func NewSSHTunnel(cfg SSHConfig) (*SSHTunnel, error) {
	authMethods, err := buildAuthMethods(cfg)
	if err != nil {
		return nil, fmt.Errorf("SSH auth: %w", err)
	}

	sshPort := cfg.Port
	if sshPort == 0 {
		sshPort = 22
	}

	sshCfg := &ssh.ClientConfig{
		User:            cfg.Username,
		Auth:            authMethods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // TODO: soporte known_hosts
	}

	client, err := ssh.Dial("tcp", fmt.Sprintf("%s:%d", cfg.Host, sshPort), sshCfg)
	if err != nil {
		return nil, fmt.Errorf("SSH dial %s:%d: %w", cfg.Host, sshPort, err)
	}

	// Listener local en puerto aleatorio asignado por el OS
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		client.Close()
		return nil, fmt.Errorf("listener local: %w", err)
	}

	localPort := listener.Addr().(*net.TCPAddr).Port
	remoteAddr := fmt.Sprintf("%s:%d", cfg.DBHost, cfg.DBPort)

	tunnel := &SSHTunnel{
		client:    client,
		listener:  listener,
		LocalPort: localPort,
	}

	// Goroutine que acepta conexiones locales y las hace forward
	go func() {
		for {
			localConn, err := listener.Accept()
			if err != nil {
				return // listener cerrado
			}
			go tunnel.forward(localConn, remoteAddr)
		}
	}()

	return tunnel, nil
}

func (t *SSHTunnel) forward(localConn net.Conn, remoteAddr string) {
	remoteConn, err := t.client.Dial("tcp", remoteAddr)
	if err != nil {
		localConn.Close()
		return
	}
	defer localConn.Close()
	defer remoteConn.Close()

	done := make(chan struct{}, 2)
	go func() { io.Copy(remoteConn, localConn); done <- struct{}{} }()
	go func() { io.Copy(localConn, remoteConn); done <- struct{}{} }()
	<-done
}

func (t *SSHTunnel) Close() {
	if t.listener != nil {
		t.listener.Close()
	}
	if t.client != nil {
		t.client.Close()
	}
}

// buildAuthMethods construye los métodos de autenticación SSH disponibles
func buildAuthMethods(cfg SSHConfig) ([]ssh.AuthMethod, error) {
	var methods []ssh.AuthMethod

	// 1. Clave privada inline (contenido PEM)
	if cfg.PrivateKey != "" {
		signer, err := parsePrivateKey(cfg.PrivateKey, "")
		if err != nil {
			return nil, fmt.Errorf("clave privada inválida: %w", err)
		}
		methods = append(methods, ssh.PublicKeys(signer))
	}

	// 2. Clave privada desde archivo
	if cfg.KeyPath != "" {
		expanded := expandHome(cfg.KeyPath)
		data, err := os.ReadFile(expanded)
		if err != nil {
			return nil, fmt.Errorf("leyendo clave %s: %w", cfg.KeyPath, err)
		}
		signer, err := parsePrivateKey(string(data), "")
		if err != nil {
			return nil, fmt.Errorf("parseando clave %s: %w", cfg.KeyPath, err)
		}
		methods = append(methods, ssh.PublicKeys(signer))
	}

	// 3. Contraseña
	if cfg.Password != "" {
		methods = append(methods, ssh.Password(cfg.Password))
		// keyboard-interactive como fallback para algunos servidores
		methods = append(methods, ssh.KeyboardInteractive(func(name, instruction string, questions []string, echos []bool) ([]string, error) {
			answers := make([]string, len(questions))
			for i := range questions {
				answers[i] = cfg.Password
			}
			return answers, nil
		}))
	}

	// 4. Fallback: intentar claves SSH del agente del sistema (~/.ssh/id_*)
	if len(methods) == 0 {
		for _, keyName := range []string{"id_ed25519", "id_rsa", "id_ecdsa"} {
			path := expandHome(filepath.Join("~", ".ssh", keyName))
			if data, err := os.ReadFile(path); err == nil {
				if signer, err := parsePrivateKey(string(data), ""); err == nil {
					methods = append(methods, ssh.PublicKeys(signer))
					break
				}
			}
		}
	}

	if len(methods) == 0 {
		return nil, fmt.Errorf("no se encontró ningún método de autenticación SSH")
	}

	return methods, nil
}

func parsePrivateKey(pemData, passphrase string) (ssh.Signer, error) {
	if passphrase != "" {
		return ssh.ParsePrivateKeyWithPassphrase([]byte(pemData), []byte(passphrase))
	}
	return ssh.ParsePrivateKey([]byte(pemData))
}

func expandHome(path string) string {
	if strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, path[2:])
		}
	}
	return path
}
