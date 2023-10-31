CREATE DATABASE viveros;

\c viveros

CREATE TABLE viveros (
    cv serial PRIMARY KEY,
    nombre varchar(50) NOT NULL,
    latitud NUMERIC NOT NULL,
    longitud NUMERIC NOT NULL
);

--cz se calcula mediante un trigger que consulta cual es el mayor cz para un cv y le incrementa uno--
CREATE TABLE zonas (
    cv integer references viveros(cv) ON DELETE CASCADE,
    cz integer,
    tipo varchar(50) NOT NULL,
    latitud NUMERIC NOT NULL,
    longitud NUMERIC NOT NULL,
    PRIMARY KEY (cv, cz)
);


CREATE TABLE productos (
    id serial PRIMARY KEY,
    nombre varchar(50) NOT NULL,
    tipo varchar(50) NOT NULL
);


--cantidad debe disminuirse cuando se hace una venta--
CREATE TABLE disponibilidad(
    cv integer references viveros(cv) ON DELETE CASCADE,
    cz integer,
    id integer references productos(id) ON DELETE CASCADE,
    precio NUMERIC NOT NULL,
    cantidad integer NOT NULL,
    PRIMARY KEY (cv, cz, id),
    FOREIGN KEY (cv, cz) REFERENCES zonas(cv, cz) ON DELETE CASCADE
);


CREATE TABLE empleados (
    dni varchar(9) PRIMARY KEY,
    nombre varchar(50) NOT NULL,
    apellidos varchar(50) NOT NULL
);



--Trigger para saber si el empleado trabaja en dos sitios en el mismo periodo de tiempo--
CREATE TABLE trabaja (
    dni varchar(9) references empleados(dni) ON DELETE CASCADE,
    cv integer references viveros(cv) ON DELETE CASCADE,
    cz integer,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    PRIMARY KEY (dni, cv, cz, fecha_inicio, fecha_fin),
    FOREIGN KEY (cv, cz) REFERENCES zonas(cv, cz) ON DELETE CASCADE,
    CONSTRAINT check_fecha CHECK (fecha_inicio <= fecha_fin)
);

--Cada venta aumenta la bonificación del cliente en 0.04, hasta un máximo de 0.20, esto se hace mediante un trigger--
--La fecha_fin se calcula mediante un trigger que suma la duración a la fecha_inicio--
CREATE TABLE clientes_plus(
    dni varchar(9) PRIMARY KEY,
    nombre varchar(50) NOT NULL,
    apellidos varchar(50) NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE,
    duracion integer NOT NULL,
    bonificacion NUMERIC DEFAULT 0
);

--Comprobar que cada id de ids corresponde a un producto que existe en disponibilidad--
CREATE TABLE vende (
    cve serial,
    dni varchar(9) references empleados(dni) ON DELETE CASCADE,
    fecha TIMESTAMP DEFAULT current_timestamp,
    ids integer[] NOT NULL,
    cantidades integer[] NOT NULL,
    dni_cliente varchar(9) references clientes_plus(dni) ON DELETE CASCADE,
    total NUMERIC,
    PRIMARY KEY (cve, dni, fecha, ids, cantidades, dni_cliente)
);



CREATE OR REPLACE FUNCTION calcular_cz()
RETURNS TRIGGER AS $$
DECLARE
    nuevo_cz integer;
BEGIN
    SELECT COALESCE(MAX(cz) + 1, 1) INTO nuevo_cz FROM zonas WHERE cv = NEW.cv;
    NEW.cz = nuevo_cz;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calcular_cz
BEFORE INSERT ON zonas
FOR EACH ROW
EXECUTE FUNCTION calcular_cz();

-- Crear una función que se ejecutará en el trigger
CREATE OR REPLACE FUNCTION actualizar_cantidad_disponibilidad()
RETURNS TRIGGER AS $$
BEGIN
    -- Recuperar las cantidades e IDs de productos de la venta
    FOR i IN 1..array_length(NEW.cantidades, 1) LOOP
        -- Disminuir la cantidad en la tabla disponibilidad
        UPDATE disponibilidad
        SET cantidad = (cantidad - NEW.cantidades[i])
        WHERE id = NEW.ids[i];

        IF (SELECT cantidad FROM disponibilidad WHERE id = NEW.ids[i]) < 0 THEN
            RAISE EXCEPTION 'No hay suficiente cantidad del producto %', NEW.ids[i];
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear un trigger que se ejecutará después de la inserción en la tabla vende
CREATE TRIGGER trigger_actualizar_cantidad_disponibilidad
AFTER INSERT ON vende
FOR EACH ROW
EXECUTE FUNCTION actualizar_cantidad_disponibilidad();

CREATE OR REPLACE FUNCTION comprobar_trabajo_existente()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM trabaja t
        WHERE t.dni = NEW.dni
        AND NEW.fecha_inicio BETWEEN t.fecha_inicio AND t.fecha_fin
    ) THEN
        RAISE EXCEPTION 'Ya existe un trabajo para el mismo DNI con un período que se superpone.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_comprobar_trabajo_existente
BEFORE INSERT ON trabaja
FOR EACH ROW
EXECUTE FUNCTION comprobar_trabajo_existente();


CREATE OR REPLACE FUNCTION comprobar_id_existente()
RETURNS TRIGGER AS $$
BEGIN
    -- Recuperar las cantidades e IDs de productos de la venta
    FOR i IN 1..array_length(NEW.ids, 1) LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM productos p
            WHERE p.id = NEW.ids[i]
        ) THEN
            RAISE EXCEPTION 'El producto % no existe.', NEW.ids[i];
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_comprobar_id_existente
BEFORE INSERT ON vende
FOR EACH ROW
EXECUTE FUNCTION comprobar_id_existente();

CREATE OR REPLACE FUNCTION calcular_total()
RETURNS TRIGGER AS $$
BEGIN
    NEW.total = 0;
    FOR i IN 1..array_length(NEW.ids, 1) LOOP
        NEW.total = NEW.total + (NEW.cantidades[i] * (SELECT precio FROM disponibilidad WHERE id = NEW.ids[i]));
    NEW.total = NEW.total - (NEW.total * (SELECT bonificacion FROM clientes_plus WHERE dni = NEW.dni_cliente));
    END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calcular_total
BEFORE INSERT ON vende
FOR EACH ROW
EXECUTE FUNCTION calcular_total();

CREATE OR REPLACE FUNCTION calcular_bonificacion()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE clientes_plus
    SET bonificacion = (bonificacion + 0.04)
    WHERE dni = NEW.dni_cliente
    AND bonificacion < 0.20;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calcular_bonificacion
AFTER INSERT ON vende
FOR EACH ROW
EXECUTE FUNCTION calcular_bonificacion();

CREATE OR REPLACE FUNCTION calcular_fecha_fin()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fecha_fin = NEW.fecha_inicio + (NEW.duracion * interval '1 month');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calcular_fecha_fin
BEFORE INSERT ON clientes_plus
FOR EACH ROW
EXECUTE FUNCTION calcular_fecha_fin();

INSERT INTO viveros (nombre, latitud, longitud) VALUES ('Vivero 1', 0, 0);
INSERT INTO viveros (nombre, latitud, longitud) VALUES ('Vivero 2', 10, 10);
INSERT INTO viveros (nombre, latitud, longitud) VALUES ('Vivero 3', 20, 20);
INSERT INTO viveros (nombre, latitud, longitud) VALUES ('Vivero 4', 30, 30);
INSERT INTO viveros (nombre, latitud, longitud) VALUES ('Vivero 5', 40, 40);

INSERT INTO zonas (cv, tipo, latitud, longitud) VALUES (1, 'Almacen', 5, 5);
INSERT INTO zonas (cv, tipo, latitud, longitud) VALUES (2, 'Almacen', 15, 15);
INSERT INTO zonas (cv, tipo, latitud, longitud) VALUES (3, 'Almacen', 25, 25);
INSERT INTO zonas (cv, tipo, latitud, longitud) VALUES (4, 'Almacen', 35, 35);
INSERT INTO zonas (cv, tipo, latitud, longitud) VALUES (5, 'Almacen', 45, 45);

INSERT INTO productos (nombre, tipo) VALUES ('Producto 1', 'Tipo 1');
INSERT INTO productos (nombre, tipo) VALUES ('Producto 2', 'Tipo 2');
INSERT INTO productos (nombre, tipo) VALUES ('Producto 3', 'Tipo 3');
INSERT INTO productos (nombre, tipo) VALUES ('Producto 4', 'Tipo 4');
INSERT INTO productos (nombre, tipo) VALUES ('Producto 5', 'Tipo 5');

INSERT INTO disponibilidad (cv, cz, id, precio, cantidad) VALUES (2, 1, 1, 10, 10);
INSERT INTO disponibilidad (cv, cz, id, precio, cantidad) VALUES (2, 1, 2, 5, 20);
INSERT INTO disponibilidad (cv, cz, id, precio, cantidad) VALUES (2, 1, 3, 15, 30);
INSERT INTO disponibilidad (cv, cz, id, precio, cantidad) VALUES (2, 1, 4, 20, 40);
INSERT INTO disponibilidad (cv, cz, id, precio, cantidad) VALUES (2, 1, 5, 25, 50);


INSERT INTO empleados (dni, nombre, apellidos) VALUES ('12345678A', 'Empleado 1', 'Apellidos 1');
INSERT INTO empleados (dni, nombre, apellidos) VALUES ('12345678B', 'Empleado 2', 'Apellidos 2');
INSERT INTO empleados (dni, nombre, apellidos) VALUES ('12345678C', 'Empleado 3', 'Apellidos 3');
INSERT INTO empleados (dni, nombre, apellidos) VALUES ('12345678D', 'Empleado 4', 'Apellidos 4');
INSERT INTO empleados (dni, nombre, apellidos) VALUES ('12345678X', 'Empleado 5', 'Apellidos 5');

INSERT INTO trabaja (dni, cv, cz, fecha_inicio, fecha_fin) VALUES ('12345678A', 2, 1, '2019-01-01', '2019-01-02');
INSERT INTO trabaja (dni, cv, cz, fecha_inicio, fecha_fin) VALUES ('12345678A', 1, 1, '2019-01-03', '2019-01-03');
INSERT INTO trabaja (dni, cv, cz, fecha_inicio, fecha_fin) VALUES ('12345678C', 2, 1, '2019-01-01', '2019-01-02');
INSERT INTO trabaja (dni, cv, cz, fecha_inicio, fecha_fin) VALUES ('12345678D', 2, 1, '2019-01-01', '2019-01-02');
INSERT INTO trabaja (dni, cv, cz, fecha_inicio, fecha_fin) VALUES ('12345678B', 2, 1, '2019-01-01', '2019-01-02');


INSERT INTO clientes_plus (dni, nombre, apellidos, fecha_inicio, duracion) VALUES ('12345678A', 'Cliente 1', 'Apellidos 1', '2019-01-01', 3);
INSERT INTO clientes_plus (dni, nombre, apellidos, fecha_inicio, duracion) VALUES ('12345678B', 'Cliente 2', 'Apellidos 2', '2019-01-01', 5);
INSERT INTO clientes_plus (dni, nombre, apellidos, fecha_inicio, duracion) VALUES ('12345678C', 'Cliente 3', 'Apellidos 3', '2019-01-01', 6);
INSERT INTO clientes_plus (dni, nombre, apellidos, fecha_inicio, duracion) VALUES ('12345678D', 'Cliente 4', 'Apellidos 4', '2019-01-01', 1);
INSERT INTO clientes_plus (dni, nombre, apellidos, fecha_inicio, duracion) VALUES ('12345678E', 'Cliente 5', 'Apellidos 5', '2019-01-01', 2);

INSERT INTO vende (dni, ids, cantidades, dni_cliente) VALUES ('12345678A', '{1, 2}', '{5, 1}', '12345678A');
INSERT INTO vende (dni, ids, cantidades, dni_cliente) VALUES ('12345678B', '{2, 3}', '{5, 1}', '12345678D');
INSERT INTO vende (dni, ids, cantidades, dni_cliente) VALUES ('12345678C', '{3, 4}', '{2, 9}', '12345678C');
INSERT INTO vende (dni, ids, cantidades, dni_cliente) VALUES ('12345678D', '{4, 5}', '{5, 3}', '12345678B');
INSERT INTO vende (dni, ids, cantidades, dni_cliente) VALUES ('12345678A', '{5, 1}', '{4, 2}', '12345678A');

SELECT * FROM viveros;

SELECT * FROM zonas;

SELECT * FROM productos;

SELECT * FROM disponibilidad;

SELECT * FROM empleados;

SELECT * FROM trabaja;

SELECT * FROM clientes_plus;

SELECT * FROM vende;