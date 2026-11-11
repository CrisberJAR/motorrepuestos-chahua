-- =====================================================================
--  MOTORREPUESTOS CHAHUA · Sistema de gestión de personal
--  Paso 1: esquema completo para el SQL Editor de Supabase
--
--  Contenido:
--    0. Extensiones
--    1. Tablas: personal, asistencias, permisos, pagos, conocimiento_empresa
--    2. Funciones auxiliares (fecha Lima, rol del usuario)
--    3. Triggers (estado de asistencia, revisión de permisos, total de pago,
--       vínculo automático auth.users -> personal)
--    4. Funciones de negocio: detalle/resumen de asistencia, planilla,
--       marcación facial, búsqueda 1:N de rostro, cierre diario de faltas
--    5. Vistas de resumen semanal y mensual
--    6. Seguridad: RLS por rol (admin / trabajador) y permisos de ejecución
--    7. Storage: buckets rostros_personal y capturas_asistencia + políticas
--    8. Realtime
--    9. Cierre automático diario (pg_cron)
--   10. Datos semilla de Motorrepuestos Chahua
--
--  Reglas de negocio aplicadas:
--    · Horario lunes a sábado 08:00 - 19:00, refrigerio 13:00 - 14:00.
--    · Tolerancia 10 min: hasta 08:10 puntual, desde 08:11 tardanza.
--    · La tardanza NO descuenta.
--    · Falta = día laborable sin entrada y sin permiso aprobado. No se paga.
--    · Permisos NO se pagan por defecto; el administrador puede marcar un
--      permiso "con goce" (con_goce = true) y entonces sí se paga.
--    · Pago = (días asistidos + días de permiso con goce) x pago_por_dia
--             - descuentos + bonos   (descuentos y bonos los fija el admin).
--    · Solo el administrador registra; los trabajadores consultan lo suyo
--      y pueden solicitar permisos (quedan pendientes).
--    · Usuario = DNI, contraseña inicial = DNI. En Supabase Auth el correo
--      interno es <dni>@chahua.pe (la app solo pide el DNI).
--
--  El script se puede volver a ejecutar sin duplicar datos.
-- =====================================================================


-- =====================================================================
-- 0. EXTENSIONES
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;
create extension if not exists vector   with schema extensions;


-- =====================================================================
-- 1. TABLAS
-- =====================================================================

-- ---------- personal ----------
create table if not exists public.personal (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid unique references auth.users(id) on delete set null,
  dni                varchar(8)  not null unique check (dni ~ '^[0-9]{8}$'),
  nombres            text        not null,
  apellidos          text        not null,
  cargo              text        not null,
  area               text        not null,
  telefono           varchar(15),
  correo             text,
  sueldo_base        numeric(10,2) not null default 0 check (sueldo_base >= 0),
  pago_por_dia       numeric(10,2) not null check (pago_por_dia >= 0),
  hora_entrada       time(0)     not null default '08:00:00',
  hora_salida        time(0)     not null default '19:00:00',
  tolerancia_min     integer     not null default 10 check (tolerancia_min between 0 and 60),
  foto_rostro_url    text,                                  -- ruta dentro del bucket rostros_personal
  descriptor_facial  extensions.vector(128),                -- embedding facial (128 valores)
  rol                text        not null default 'trabajador' check (rol in ('admin','trabajador')),
  estado             text        not null default 'activo'     check (estado in ('activo','inactivo')),
  fecha_ingreso      date        not null default current_date,
  created_at         timestamptz not null default now()
);
comment on column public.personal.foto_rostro_url   is 'Ruta del archivo en el bucket privado rostros_personal, p. ej. <personal_id>/rostro.jpg';
comment on column public.personal.descriptor_facial is 'Vector facial de 128 dimensiones generado por el endpoint de IA; se compara por distancia euclidiana';

-- ---------- asistencias ----------
create table if not exists public.asistencias (
  id                  uuid primary key default gen_random_uuid(),
  personal_id         uuid not null references public.personal(id) on delete cascade,
  fecha               date not null default ((now() at time zone 'America/Lima')::date),
  hora_entrada        time(0),
  hora_salida         time(0),
  estado              text not null default 'asistio' check (estado in ('asistio','tardanza','falta','permiso')),
  confianza_facial    numeric(5,2) check (confianza_facial between 0 and 100),
  foto_evidencia_url  text,                                 -- ruta dentro del bucket capturas_asistencia
  created_at          timestamptz not null default now(),
  constraint asistencias_unica_por_dia unique (personal_id, fecha),
  constraint asistencias_salida_despues check (hora_salida is null or hora_entrada is null or hora_salida >= hora_entrada)
);
create index if not exists asistencias_fecha_idx on public.asistencias (fecha);

-- ---------- permisos ----------
create table if not exists public.permisos (
  id               uuid primary key default gen_random_uuid(),
  personal_id      uuid not null references public.personal(id) on delete cascade,
  tipo_permiso     text not null check (tipo_permiso in ('salud','personal','urgencia','vacaciones')),
  fecha_inicio     date not null,
  fecha_fin        date not null,
  motivo           text not null,
  estado           text not null default 'pendiente' check (estado in ('pendiente','aprobado','rechazado')),
  origen           text not null default 'web' check (origen in ('movil','web','chatbot_movil','chatbot_web')),
  con_goce         boolean not null default false,          -- true = el admin decidió pagar estos días
  revisado_por     uuid references public.personal(id) on delete set null,
  fecha_revision   timestamptz,
  observacion      text,
  created_at       timestamptz not null default now(),
  constraint permisos_rango_valido check (fecha_fin >= fecha_inicio)
);
create index if not exists permisos_personal_estado_idx on public.permisos (personal_id, estado);
create index if not exists permisos_fechas_idx on public.permisos (fecha_inicio, fecha_fin);

-- ---------- pagos ----------
create table if not exists public.pagos (
  id                     uuid primary key default gen_random_uuid(),
  personal_id            uuid not null references public.personal(id) on delete cascade,
  periodo_mes            text not null check (periodo_mes ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  dias_asistidos         integer not null default 0,        -- incluye días con tardanza
  dias_permiso           integer not null default 0,
  dias_permiso_pagado    integer not null default 0,        -- permisos con goce
  dias_falta             integer not null default 0,
  tardanzas_acumuladas   integer not null default 0,
  pago_por_dia           numeric(10,2) not null default 0,  -- tarifa usada en el cálculo
  monto_base             numeric(10,2) not null default 0,  -- (asistidos + permiso pagado) x pago_por_dia
  descuentos             numeric(10,2) not null default 0 check (descuentos >= 0),
  bonos                  numeric(10,2) not null default 0 check (bonos >= 0),
  total_pagar            numeric(10,2) not null default 0,
  estado_pago            text not null default 'pendiente' check (estado_pago in ('pendiente','pagado')),
  fecha_pago             date,
  observacion            text,
  created_at             timestamptz not null default now(),
  constraint pagos_unico_por_periodo unique (personal_id, periodo_mes)
);
create index if not exists pagos_periodo_idx on public.pagos (periodo_mes);

-- ---------- conocimiento_empresa ----------
create table if not exists public.conocimiento_empresa (
  id                  uuid primary key default gen_random_uuid(),
  categoria           text not null,
  pregunta_frecuente  text not null,
  respuesta_politica  text not null,
  activo              boolean not null default true,
  created_at          timestamptz not null default now(),
  constraint conocimiento_unico unique (categoria, pregunta_frecuente)
);


-- =====================================================================
-- 2. FUNCIONES AUXILIARES
-- =====================================================================

-- Fecha actual en Perú
create or replace function public.hoy_lima()
returns date
language sql stable
set search_path = public
as $$
  select (now() at time zone 'America/Lima')::date;
$$;

-- ¿El usuario autenticado es administrador activo?
create or replace function public.es_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.personal
    where user_id = auth.uid() and rol = 'admin' and estado = 'activo'
  );
$$;

-- id de la tabla personal del usuario autenticado
create or replace function public.mi_personal_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select id from public.personal where user_id = auth.uid() limit 1;
$$;

-- Puede ejecutar acciones administrativas:
--   · administrador autenticado
--   · backend con service_role (endpoints de Vercel)
--   · conexión directa a la base (SQL Editor, pg_cron), donde no hay JWT
create or replace function public.puede_administrar()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select auth.jwt() is null
      or coalesce(auth.jwt() ->> 'role', '') = 'service_role'
      or public.es_admin();
$$;


-- =====================================================================
-- 3. TRIGGERS
-- =====================================================================

-- 3.1 Estado de la asistencia según hora de entrada y tolerancia
create or replace function public.asistencias_calcular_estado()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_hora_entrada time;
  v_tolerancia   integer;
begin
  if new.hora_entrada is not null
     and (tg_op = 'INSERT' or new.hora_entrada is distinct from old.hora_entrada or new.estado is null) then
    select p.hora_entrada, p.tolerancia_min
      into v_hora_entrada, v_tolerancia
      from public.personal p
     where p.id = new.personal_id;

    -- 08:00 + 10 min de tolerancia: 08:10 puntual, 08:11 tardanza
    if new.hora_entrada >= v_hora_entrada + make_interval(mins => v_tolerancia + 1) then
      new.estado := 'tardanza';
    else
      new.estado := 'asistio';
    end if;
  elsif new.estado is null then
    new.estado := 'falta';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_asistencias_estado on public.asistencias;
create trigger trg_asistencias_estado
  before insert or update on public.asistencias
  for each row execute function public.asistencias_calcular_estado();

-- 3.2 Registro de quién y cuándo aprobó o rechazó un permiso
create or replace function public.permisos_registrar_revision()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.estado is distinct from old.estado and new.estado in ('aprobado','rechazado') then
    new.fecha_revision := now();
    new.revisado_por   := coalesce(public.mi_personal_id(), new.revisado_por);
  elsif new.estado = 'pendiente' then
    new.fecha_revision := null;
    new.revisado_por   := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_permisos_revision on public.permisos;
create trigger trg_permisos_revision
  before update on public.permisos
  for each row execute function public.permisos_registrar_revision();

-- 3.3 Total a pagar siempre coherente con base, descuentos y bonos
create or replace function public.pagos_calcular_total()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.total_pagar := greatest(0, coalesce(new.monto_base,0) - coalesce(new.descuentos,0) + coalesce(new.bonos,0));
  if new.estado_pago = 'pagado' and new.fecha_pago is null then
    new.fecha_pago := public.hoy_lima();
  elsif new.estado_pago = 'pendiente' then
    new.fecha_pago := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_pagos_total on public.pagos;
create trigger trg_pagos_total
  before insert or update on public.pagos
  for each row execute function public.pagos_calcular_total();

-- 3.4 Al crear un usuario en Supabase Auth (<dni>@chahua.pe) se vincula con su fila en personal
create or replace function public.vincular_usuario_personal()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  update public.personal
     set user_id = new.id
   where dni = split_part(new.email, '@', 1)
     and user_id is null;
  return new;
end;
$$;

drop trigger if exists trg_vincular_usuario_personal on auth.users;
create trigger trg_vincular_usuario_personal
  after insert on auth.users
  for each row execute function public.vincular_usuario_personal();


-- =====================================================================
-- 4. FUNCIONES DE NEGOCIO
-- =====================================================================

-- 4.1 Detalle día por día (lunes a sábado) de cada trabajador en un rango.
--     Estados: asistio, tardanza, permiso, falta, pendiente (hoy sin marcar), futuro.
--     Respeta RLS: un trabajador solo obtiene sus propias filas.
create or replace function public.detalle_asistencia(
  p_desde       date,
  p_hasta       date,
  p_personal_id uuid default null
)
returns table (
  personal_id       uuid,
  dni               text,
  nombres           text,
  apellidos         text,
  cargo             text,
  area              text,
  fecha             date,
  dia_semana        integer,
  estado            text,
  hora_entrada      time,
  hora_salida       time,
  confianza_facial  numeric,
  permiso_id        uuid,
  permiso_tipo      text,
  permiso_con_goce  boolean
)
language sql stable security invoker
set search_path = public
as $$
  with dias as (
    select g::date as fecha
      from generate_series(p_desde::timestamp, p_hasta::timestamp, interval '1 day') g
     where extract(isodow from g) < 7
  )
  select
    p.id,
    p.dni::text,
    p.nombres,
    p.apellidos,
    p.cargo,
    p.area,
    dias.fecha,
    extract(isodow from dias.fecha)::integer,
    case
      when a.estado is not null and a.estado <> 'falta' then a.estado
      when pe.id is not null                           then 'permiso'
      when a.estado = 'falta'                          then 'falta'
      when dias.fecha <  public.hoy_lima()             then 'falta'
      when dias.fecha =  public.hoy_lima()             then 'pendiente'
      else 'futuro'
    end,
    a.hora_entrada,
    a.hora_salida,
    a.confianza_facial,
    pe.id,
    pe.tipo_permiso,
    coalesce(pe.con_goce, false)
  from public.personal p
  cross join dias
  left join public.asistencias a
         on a.personal_id = p.id and a.fecha = dias.fecha
  left join lateral (
         select x.id, x.tipo_permiso, x.con_goce
           from public.permisos x
          where x.personal_id = p.id
            and x.estado = 'aprobado'
            and dias.fecha between x.fecha_inicio and x.fecha_fin
          order by x.created_at desc
          limit 1
       ) pe on true
  where dias.fecha >= p.fecha_ingreso
    and ((p_personal_id is null and p.estado = 'activo') or p.id = p_personal_id)
  order by p.apellidos, p.nombres, dias.fecha;
$$;

-- 4.2 Resumen por trabajador para cualquier rango (semana, mes, etc.)
create or replace function public.resumen_asistencia(
  p_desde       date,
  p_hasta       date,
  p_personal_id uuid default null
)
returns table (
  personal_id        uuid,
  dni                text,
  nombres            text,
  apellidos          text,
  cargo              text,
  area               text,
  desde              date,
  hasta              date,
  dias_laborables    integer,
  dias_asistidos     integer,
  tardanzas          integer,
  dias_permiso       integer,
  dias_falta         integer,
  fechas_tardanza    date[],
  fechas_permiso     date[],
  fechas_falta       date[]
)
language sql stable security invoker
set search_path = public
as $$
  select
    d.personal_id,
    d.dni,
    d.nombres,
    d.apellidos,
    d.cargo,
    d.area,
    p_desde,
    p_hasta,
    count(*) filter (where d.estado not in ('futuro','pendiente'))::integer,
    count(*) filter (where d.estado in ('asistio','tardanza'))::integer,
    count(*) filter (where d.estado = 'tardanza')::integer,
    count(*) filter (where d.estado = 'permiso')::integer,
    count(*) filter (where d.estado = 'falta')::integer,
    coalesce(array_agg(d.fecha order by d.fecha) filter (where d.estado = 'tardanza'), '{}'::date[]),
    coalesce(array_agg(d.fecha order by d.fecha) filter (where d.estado = 'permiso'),  '{}'::date[]),
    coalesce(array_agg(d.fecha order by d.fecha) filter (where d.estado = 'falta'),    '{}'::date[])
  from public.detalle_asistencia(p_desde, p_hasta, p_personal_id) d
  group by d.personal_id, d.dni, d.nombres, d.apellidos, d.cargo, d.area
  order by d.apellidos, d.nombres;
$$;

-- 4.3 Genera o recalcula la planilla de un mes (AAAA-MM).
--     No toca los pagos ya marcados como pagados.
--     Conserva los descuentos y bonos que el admin haya ingresado.
create or replace function public.generar_planilla(p_periodo text)
returns setof public.pagos
language plpgsql security definer
set search_path = public
as $$
declare
  v_desde date;
  v_hasta date;
  r       record;
begin
  if not public.puede_administrar() then
    raise exception 'Solo el administrador puede generar la planilla';
  end if;
  if p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Periodo inválido: usa el formato AAAA-MM, por ejemplo 2026-11';
  end if;

  v_desde := to_date(p_periodo || '-01', 'YYYY-MM-DD');
  v_hasta := least((v_desde + interval '1 month' - interval '1 day')::date, public.hoy_lima());

  for r in
    select p.id,
           p.pago_por_dia,
           count(*) filter (where d.estado in ('asistio','tardanza'))           as asistidos,
           count(*) filter (where d.estado = 'permiso')                         as permisos,
           count(*) filter (where d.estado = 'permiso' and d.permiso_con_goce)  as permisos_pagados,
           count(*) filter (where d.estado = 'falta')                           as faltas,
           count(*) filter (where d.estado = 'tardanza')                        as tardanzas
      from public.personal p
      join public.detalle_asistencia(v_desde, v_hasta, null) d on d.personal_id = p.id
     where p.estado = 'activo'
     group by p.id, p.pago_por_dia
  loop
    insert into public.pagos as pg (
      personal_id, periodo_mes, dias_asistidos, dias_permiso, dias_permiso_pagado,
      dias_falta, tardanzas_acumuladas, pago_por_dia, monto_base
    )
    values (
      r.id, p_periodo, r.asistidos, r.permisos, r.permisos_pagados,
      r.faltas, r.tardanzas, r.pago_por_dia,
      (r.asistidos + r.permisos_pagados) * r.pago_por_dia
    )
    on conflict (personal_id, periodo_mes) do update
       set dias_asistidos       = excluded.dias_asistidos,
           dias_permiso         = excluded.dias_permiso,
           dias_permiso_pagado  = excluded.dias_permiso_pagado,
           dias_falta           = excluded.dias_falta,
           tardanzas_acumuladas = excluded.tardanzas_acumuladas,
           pago_por_dia         = excluded.pago_por_dia,
           monto_base           = excluded.monto_base
     where pg.estado_pago = 'pendiente'
       and (pg.dias_asistidos, pg.dias_permiso, pg.dias_permiso_pagado, pg.dias_falta,
            pg.tardanzas_acumuladas, pg.pago_por_dia, pg.monto_base)
           is distinct from
           (excluded.dias_asistidos, excluded.dias_permiso, excluded.dias_permiso_pagado, excluded.dias_falta,
            excluded.tardanzas_acumuladas, excluded.pago_por_dia, excluded.monto_base);
  end loop;

  return query
    select pg.* from public.pagos pg where pg.periodo_mes = p_periodo;
end;
$$;

-- 4.4 Marcación por reconocimiento facial (la llama /api/ia/identificar-rostro).
--     1er escaneo del día = entrada; siguiente = salida (si pasaron 30 min).
create or replace function public.registrar_marcacion(
  p_personal_id  uuid,
  p_confianza    numeric,
  p_foto_url     text default null
)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_hoy   date := public.hoy_lima();
  v_hora  time := date_trunc('second', now() at time zone 'America/Lima')::time;
  v_per   public.personal;
  v_asi   public.asistencias;
  v_tipo  text;
begin
  if not public.puede_administrar() then
    raise exception 'Solo el administrador puede registrar asistencia';
  end if;

  select * into v_per from public.personal where id = p_personal_id and estado = 'activo';
  if not found then
    raise exception 'Trabajador no encontrado o inactivo';
  end if;

  if extract(isodow from v_hoy) = 7 then
    return jsonb_build_object('tipo', 'no_laborable', 'mensaje', 'Hoy es domingo: no se registra asistencia.');
  end if;

  select * into v_asi from public.asistencias
   where personal_id = p_personal_id and fecha = v_hoy
   for update;

  if not found then
    insert into public.asistencias (personal_id, fecha, hora_entrada, confianza_facial, foto_evidencia_url)
    values (p_personal_id, v_hoy, v_hora, p_confianza, p_foto_url)
    returning * into v_asi;
    v_tipo := 'entrada';

  elsif v_asi.hora_entrada is null then
    -- había un registro de falta/permiso y el trabajador llegó
    update public.asistencias
       set hora_entrada = v_hora, estado = null,
           confianza_facial = p_confianza, foto_evidencia_url = coalesce(p_foto_url, foto_evidencia_url)
     where id = v_asi.id
    returning * into v_asi;
    v_tipo := 'entrada';

  elsif v_asi.hora_salida is null then
    if v_hora - v_asi.hora_entrada < interval '30 minutes' then
      v_tipo := 'duplicado';
    else
      update public.asistencias set hora_salida = v_hora where id = v_asi.id returning * into v_asi;
      v_tipo := 'salida';
    end if;

  else
    v_tipo := 'completo';
  end if;

  return jsonb_build_object(
    'tipo', v_tipo,
    'mensaje', case v_tipo
                 when 'entrada'   then 'Entrada registrada'
                 when 'salida'    then 'Salida registrada'
                 when 'duplicado' then 'Ya tiene entrada registrada hace menos de 30 minutos'
                 else 'Ya registró entrada y salida hoy'
               end,
    'asistencia', to_jsonb(v_asi),
    'trabajador', jsonb_build_object(
        'id', v_per.id, 'dni', v_per.dni, 'nombres', v_per.nombres, 'apellidos', v_per.apellidos,
        'cargo', v_per.cargo, 'area', v_per.area, 'foto_rostro_url', v_per.foto_rostro_url)
  );
end;
$$;

-- 4.5 Búsqueda 1:N: los rostros registrados más parecidos a un descriptor.
--     Solo la usa el backend (service_role).
create or replace function public.buscar_rostro(
  p_descriptor extensions.vector,
  p_limite     integer default 3
)
returns table (
  personal_id      uuid,
  dni              text,
  nombres          text,
  apellidos        text,
  cargo            text,
  foto_rostro_url  text,
  distancia        double precision
)
language sql stable security definer
set search_path = public, extensions
as $$
  select p.id, p.dni::text, p.nombres, p.apellidos, p.cargo, p.foto_rostro_url,
         (p.descriptor_facial <-> p_descriptor)::double precision
    from public.personal p
   where p.estado = 'activo'
     and p.descriptor_facial is not null
   order by p.descriptor_facial <-> p_descriptor
   limit greatest(1, least(p_limite, 10));
$$;

-- 4.6 Cierre del día: deja registrada la falta (o el permiso) de quien no marcó.
create or replace function public.cerrar_dia(p_fecha date default null)
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  v_fecha date := coalesce(p_fecha, public.hoy_lima());
  v_filas integer;
begin
  if extract(isodow from v_fecha) = 7 then
    return 0;
  end if;

  insert into public.asistencias (personal_id, fecha, estado)
  select p.id,
         v_fecha,
         case when exists (
                select 1 from public.permisos x
                 where x.personal_id = p.id and x.estado = 'aprobado'
                   and v_fecha between x.fecha_inicio and x.fecha_fin)
              then 'permiso' else 'falta' end
    from public.personal p
   where p.estado = 'activo'
     and p.fecha_ingreso <= v_fecha
     and not exists (select 1 from public.asistencias a where a.personal_id = p.id and a.fecha = v_fecha)
  on conflict (personal_id, fecha) do nothing;

  get diagnostics v_filas = row_count;
  return v_filas;
end;
$$;


-- =====================================================================
-- 5. VISTAS DE RESUMEN (respetan RLS del usuario que consulta)
-- =====================================================================
create or replace view public.v_asistencia_semana_actual
with (security_invoker = true) as
  select *
    from public.resumen_asistencia(
           public.hoy_lima() - (extract(isodow from public.hoy_lima())::integer - 1),
           public.hoy_lima() - (extract(isodow from public.hoy_lima())::integer - 1) + 5,
           null);

create or replace view public.v_asistencia_mes_actual
with (security_invoker = true) as
  select *
    from public.resumen_asistencia(
           make_date(extract(year from public.hoy_lima())::integer, extract(month from public.hoy_lima())::integer, 1),
           (make_date(extract(year from public.hoy_lima())::integer, extract(month from public.hoy_lima())::integer, 1)
              + interval '1 month' - interval '1 day')::date,
           null);


-- =====================================================================
-- 6. SEGURIDAD: RLS Y PERMISOS DE EJECUCIÓN
-- =====================================================================
alter table public.personal             enable row level security;
alter table public.asistencias          enable row level security;
alter table public.permisos             enable row level security;
alter table public.pagos                enable row level security;
alter table public.conocimiento_empresa enable row level security;

-- ---------- personal ----------
drop policy if exists personal_admin_todo   on public.personal;
drop policy if exists personal_ver_propio   on public.personal;
create policy personal_admin_todo on public.personal
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));
create policy personal_ver_propio on public.personal
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------- asistencias ----------
drop policy if exists asistencias_admin_todo on public.asistencias;
drop policy if exists asistencias_ver_propio on public.asistencias;
create policy asistencias_admin_todo on public.asistencias
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));
create policy asistencias_ver_propio on public.asistencias
  for select to authenticated
  using (personal_id = (select public.mi_personal_id()));

-- ---------- permisos ----------
drop policy if exists permisos_admin_todo         on public.permisos;
drop policy if exists permisos_ver_propio         on public.permisos;
drop policy if exists permisos_solicitar_propio   on public.permisos;
create policy permisos_admin_todo on public.permisos
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));
create policy permisos_ver_propio on public.permisos
  for select to authenticated
  using (personal_id = (select public.mi_personal_id()));
create policy permisos_solicitar_propio on public.permisos
  for insert to authenticated
  with check (
    personal_id = (select public.mi_personal_id())
    and estado = 'pendiente'
    and con_goce = false
    and origen in ('movil','web')
  );

-- ---------- pagos ----------
drop policy if exists pagos_admin_todo on public.pagos;
drop policy if exists pagos_ver_propio on public.pagos;
create policy pagos_admin_todo on public.pagos
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));
create policy pagos_ver_propio on public.pagos
  for select to authenticated
  using (personal_id = (select public.mi_personal_id()));

-- ---------- conocimiento_empresa ----------
drop policy if exists conocimiento_leer        on public.conocimiento_empresa;
drop policy if exists conocimiento_admin_todo  on public.conocimiento_empresa;
create policy conocimiento_leer on public.conocimiento_empresa
  for select to authenticated
  using (activo or (select public.es_admin()));
create policy conocimiento_admin_todo on public.conocimiento_empresa
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ---------- sin acceso anónimo ----------
revoke all on public.personal, public.asistencias, public.permisos, public.pagos, public.conocimiento_empresa from anon;
revoke all on public.v_asistencia_semana_actual, public.v_asistencia_mes_actual from anon;
grant select on public.v_asistencia_semana_actual, public.v_asistencia_mes_actual to authenticated;

-- ---------- ejecución de funciones ----------
revoke execute on function public.hoy_lima()                                  from public, anon;
revoke execute on function public.es_admin()                                  from public, anon;
revoke execute on function public.mi_personal_id()                            from public, anon;
revoke execute on function public.puede_administrar()                         from public, anon;
revoke execute on function public.detalle_asistencia(date, date, uuid)        from public, anon;
revoke execute on function public.resumen_asistencia(date, date, uuid)        from public, anon;
revoke execute on function public.generar_planilla(text)                      from public, anon;
revoke execute on function public.registrar_marcacion(uuid, numeric, text)    from public, anon;
revoke execute on function public.buscar_rostro(extensions.vector, integer)   from public, anon, authenticated;
revoke execute on function public.cerrar_dia(date)                            from public, anon, authenticated;

grant execute on function public.hoy_lima()                                   to authenticated, service_role;
grant execute on function public.es_admin()                                   to authenticated, service_role;
grant execute on function public.mi_personal_id()                             to authenticated, service_role;
grant execute on function public.puede_administrar()                          to authenticated, service_role;
grant execute on function public.detalle_asistencia(date, date, uuid)         to authenticated, service_role;
grant execute on function public.resumen_asistencia(date, date, uuid)         to authenticated, service_role;
grant execute on function public.generar_planilla(text)                       to authenticated, service_role;
grant execute on function public.registrar_marcacion(uuid, numeric, text)     to authenticated, service_role;
grant execute on function public.buscar_rostro(extensions.vector, integer)    to service_role;
grant execute on function public.cerrar_dia(date)                             to service_role;


-- =====================================================================
-- 7. STORAGE: BUCKETS PRIVADOS Y POLÍTICAS
--    Estructura de rutas:
--      rostros_personal/<personal_id>/rostro.jpg
--      capturas_asistencia/<personal_id>/<AAAA-MM-DD>_<hhmmss>.jpg
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('rostros_personal',    'rostros_personal',    false, 5242880, array['image/jpeg','image/png','image/webp']),
  ('capturas_asistencia', 'capturas_asistencia', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists chahua_storage_admin_todo        on storage.objects;
drop policy if exists chahua_storage_trabajador_propio on storage.objects;

create policy chahua_storage_admin_todo on storage.objects
  for all to authenticated
  using      (bucket_id in ('rostros_personal','capturas_asistencia') and (select public.es_admin()))
  with check (bucket_id in ('rostros_personal','capturas_asistencia') and (select public.es_admin()));

create policy chahua_storage_trabajador_propio on storage.objects
  for select to authenticated
  using (
    bucket_id in ('rostros_personal','capturas_asistencia')
    and (storage.foldername(name))[1] = (select public.mi_personal_id())::text
  );


-- =====================================================================
-- 8. REALTIME (web y móvil reciben los cambios al instante)
-- =====================================================================
alter table public.personal    replica identity full;
alter table public.asistencias replica identity full;
alter table public.permisos    replica identity full;
alter table public.pagos       replica identity full;

do $$
declare
  t text;
begin
  foreach t in array array['personal','asistencias','permisos','pagos'] loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;


-- =====================================================================
-- 9. CIERRE AUTOMÁTICO DIARIO CON pg_cron
--    Corre a las 00:30 UTC = 19:30 hora de Lima (después de la salida).
--    Si pg_cron no está disponible, el script continúa: las faltas igual
--    se calculan en detalle_asistencia().
-- =====================================================================
do $$
begin
  create extension if not exists pg_cron;
  if exists (select 1 from cron.job where jobname = 'chahua_cerrar_dia') then
    perform cron.unschedule('chahua_cerrar_dia');
  end if;
  perform cron.schedule(
    'chahua_cerrar_dia',
    '30 0 * * *',
    $cron$select public.cerrar_dia((now() at time zone 'America/Lima')::date)$cron$
  );
exception when others then
  raise notice 'pg_cron no se pudo configurar (%). Actívalo en Database > Extensions si quieres el cierre automático.', sqlerrm;
end;
$$;


-- =====================================================================
-- 10. DATOS SEMILLA · MOTORREPUESTOS CHAHUA
-- =====================================================================

-- 10.1 Personal (contraseña inicial = DNI; los usuarios se crean con supabase/crear-usuarios.mjs)
insert into public.personal
  (dni, nombres, apellidos, cargo, area, telefono, correo, sueldo_base, pago_por_dia,
   hora_entrada, hora_salida, tolerancia_min, rol, estado, fecha_ingreso)
values
  ('45781236', 'Ricardo Manuel',   'Torres Vílchez',   'Administrador',         'Administración', '987451236', 'rtorres@motorrepuestoschahua.pe',  2080.00, 80.00, '08:00', '19:00', 10, 'admin',      'activo', '2022-03-01'),
  ('72345678', 'Carlos Alberto',   'Gómez Huamán',     'Vendedor de Repuestos', 'Ventas',         '956234781', 'cgomez@motorrepuestoschahua.pe',   1560.00, 60.00, '08:00', '19:00', 10, 'trabajador', 'activo', '2023-07-17'),
  ('70984512', 'José Antonio',     'Ramos Cárdenas',   'Mecánico Especialista', 'Taller',         '945871203', 'jramos@motorrepuestoschahua.pe',   1950.00, 75.00, '08:00', '19:00', 10, 'trabajador', 'activo', '2021-11-08'),
  ('73561249', 'Miguel Ángel',     'Paredes Soto',     'Almacenero',            'Almacén',        '932560418', 'mparedes@motorrepuestoschahua.pe', 1430.00, 55.00, '08:00', '19:00', 10, 'trabajador', 'activo', '2024-02-05'),
  ('71239845', 'Lucía Fernanda',   'Mendoza Rojas',    'Cajera',                'Caja',           '961347520', 'lmendoza@motorrepuestoschahua.pe', 1300.00, 50.00, '08:00', '19:00', 10, 'trabajador', 'activo', '2024-09-16')
on conflict (dni) do nothing;

-- 10.2 Permisos de ejemplo (solo si la tabla está vacía)
insert into public.permisos (personal_id, tipo_permiso, fecha_inicio, fecha_fin, motivo, estado, origen, con_goce, created_at)
select p.id, v.tipo, v.ini::date, v.fin::date, v.motivo, v.estado, v.origen, v.goce, v.creado::timestamptz
  from (values
    ('72345678', 'salud',      '2026-10-14', '2026-10-14', 'Cita médica en EsSalud',                          'aprobado',  'chatbot_movil', false, '2026-10-12 09:15:00-05'),
    ('70984512', 'salud',      '2026-10-27', '2026-10-28', 'Descanso médico por lumbalgia',                   'aprobado',  'web',           true,  '2026-10-26 18:40:00-05'),
    ('71239845', 'personal',   '2026-10-31', '2026-10-31', 'Viaje familiar a Huancayo',                       'rechazado', 'movil',         false, '2026-10-27 12:05:00-05'),
    ('71239845', 'personal',   '2026-11-04', '2026-11-04', 'Trámite de DNI en RENIEC',                        'aprobado',  'movil',         false, '2026-11-02 08:30:00-05'),
    ('73561249', 'urgencia',   '2026-11-10', '2026-11-10', 'Hijo con fiebre, atención en el centro de salud', 'pendiente', 'chatbot_web',   false, '2026-11-09 07:10:00-05'),
    ('72345678', 'personal',   '2026-11-14', '2026-11-14', 'Trámite de licencia de conducir',                 'pendiente', 'web',           false, '2026-11-08 16:20:00-05'),
    ('70984512', 'vacaciones', '2026-11-23', '2026-11-28', 'Vacaciones programadas',                          'pendiente', 'web',           false, '2026-11-05 10:00:00-05')
  ) as v(dni, tipo, ini, fin, motivo, estado, origen, goce, creado)
  join public.personal p on p.dni = v.dni
 where not exists (select 1 from public.permisos);

-- 10.3 Asistencias del 1 de octubre al 7 de noviembre de 2026 (lunes a sábado).
--      Distribución realista y reproducible: ~4 % faltas, ~10 % tardanzas.
--      El estado asistio/tardanza lo calcula el trigger según la hora.
insert into public.asistencias (personal_id, fecha, hora_entrada, hora_salida, estado, confianza_facial)
select p.id,
       g::date,
       case when h.v < 4  then null
            when h.v < 14 then (time '08:11' + make_interval(mins => (h.v * 7) % 25))::time(0)
            else              (time '07:40' + make_interval(mins => (h.v * 3) % 31))::time(0) end,
       case when h.v < 4  then null
            else              (time '19:00' + make_interval(mins => (h.v * 5) % 15))::time(0) end,
       case when h.v < 4  then 'falta' else null end,
       case when h.v < 4  then null else round(95 + ((h.v * 13) % 46) / 10.0, 2) end
  from public.personal p
 cross join generate_series(timestamp '2026-10-01', timestamp '2026-11-07', interval '1 day') g
 cross join lateral (select (abs(hashtext(p.dni || g::date::text)::bigint) % 100)::integer as v) h
 where extract(isodow from g) < 7
   and g::date >= p.fecha_ingreso
   and not exists (
         select 1 from public.permisos x
          where x.personal_id = p.id and x.estado = 'aprobado'
            and g::date between x.fecha_inicio and x.fecha_fin)
on conflict (personal_id, fecha) do nothing;

-- Días con permiso aprobado ya transcurridos
insert into public.asistencias (personal_id, fecha, estado)
select x.personal_id, g::date, 'permiso'
  from public.permisos x
 cross join lateral generate_series(x.fecha_inicio::timestamp, least(x.fecha_fin, date '2026-11-07')::timestamp, interval '1 day') g
 where x.estado = 'aprobado'
   and extract(isodow from g) < 7
on conflict (personal_id, fecha) do nothing;

-- 10.4 Planilla de octubre (cerrada) y noviembre (en curso)
select public.generar_planilla('2026-10');
select public.generar_planilla('2026-11');

update public.pagos
   set estado_pago = 'pagado', fecha_pago = '2026-11-05'
 where periodo_mes = '2026-10'
   and estado_pago = 'pendiente'
   and personal_id in (select id from public.personal where dni in ('45781236','70984512','71239845'));

-- 10.5 Base de conocimiento para el asistente (Gemini)
insert into public.conocimiento_empresa (categoria, pregunta_frecuente, respuesta_politica)
values
  ('Horario',    '¿Cuál es el horario de trabajo?',
   'En Motorrepuestos Chahua se trabaja de lunes a sábado de 08:00 a. m. a 07:00 p. m., con una hora de refrigerio de 1:00 p. m. a 2:00 p. m. Los domingos no se labora.'),
  ('Tolerancia', '¿Cuántos minutos de tolerancia hay para llegar?',
   'Hay 10 minutos de tolerancia. Si la entrada se registra hasta las 08:10 a. m. es puntual; desde las 08:11 a. m. se registra como tardanza.'),
  ('Tardanzas',  '¿Las tardanzas tienen descuento?',
   'No. Las tardanzas no generan descuento en el pago. Se registran y se acumulan en el historial de asistencia y en la planilla del mes como control.'),
  ('Asistencia', '¿Cómo se registra mi asistencia?',
   'El administrador registra la entrada y la salida escaneando tu rostro con la cámara de su celular. El sistema te identifica automáticamente y guarda la hora y el porcentaje de coincidencia. El personal no marca asistencia desde su propio celular.'),
  ('Faltas',     '¿Qué pasa si falto un día?',
   'Un día laborable (lunes a sábado) sin registro de entrada y sin permiso aprobado se considera falta. Los días de falta no se pagan.'),
  ('Permisos',   '¿Cómo solicito un permiso?',
   'Puedes solicitarlo desde la app móvil, desde la web o escribiéndole al chatbot indicando tu DNI, la fecha y el motivo. Los tipos son: salud, personal, urgencia y vacaciones. La solicitud queda pendiente hasta que el administrador la apruebe o la rechace.'),
  ('Permisos',   '¿Los días de permiso se pagan?',
   'Por defecto, los días de permiso no se pagan. El administrador puede decidir pagar un permiso en particular (permiso con goce); en ese caso esos días se suman al pago del mes.'),
  ('Pagos',      '¿Cómo se calcula mi pago del mes?',
   'Pago del mes = (días asistidos + días de permiso con goce) × tu pago por día − descuentos + bonos. Los días con tardanza cuentan como días asistidos. Las faltas y los permisos sin goce no se pagan. Los descuentos y bonos los registra el administrador.'),
  ('Pagos',      '¿Cómo sé si ya me pagaron?',
   'En el módulo de Pagos de la app o de la web verás el estado de cada mes: "pendiente" o "pagado" con la fecha de pago. También puedes preguntárselo al chatbot.'),
  ('Acceso',     '¿Cómo ingreso a la app y a la web?',
   'Tu usuario es tu DNI y tu contraseña inicial también es tu DNI. Solo el administrador puede cambiar las contraseñas.')
on conflict (categoria, pregunta_frecuente) do update
  set respuesta_politica = excluded.respuesta_politica, activo = true;


-- =====================================================================
-- VERIFICACIÓN RÁPIDA (debe mostrar 5 trabajadores con su resumen de octubre)
-- =====================================================================
select r.dni, r.nombres, r.apellidos, r.dias_asistidos, r.tardanzas, r.dias_permiso, r.dias_falta,
       pg.total_pagar as pago_octubre, pg.estado_pago
  from public.resumen_asistencia('2026-10-01', '2026-10-31') r
  left join public.pagos pg on pg.personal_id = r.personal_id and pg.periodo_mes = '2026-10'
 order by r.apellidos;
