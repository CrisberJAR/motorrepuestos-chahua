-- Paso 2 · Ajuste de la búsqueda facial 1:N
-- Devuelve además la similitud coseno (0 a 1) que se muestra como "% de coincidencia".
drop function if exists public.buscar_rostro(extensions.vector, integer);

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
  area             text,
  foto_rostro_url  text,
  distancia        double precision,
  similitud        double precision
)
language sql stable security definer
set search_path = public, extensions
as $$
  select p.id, p.dni::text, p.nombres, p.apellidos, p.cargo, p.area, p.foto_rostro_url,
         (p.descriptor_facial <-> p_descriptor)::double precision,
         (1 - (p.descriptor_facial <=> p_descriptor))::double precision
    from public.personal p
   where p.estado = 'activo'
     and p.descriptor_facial is not null
   order by p.descriptor_facial <-> p_descriptor
   limit greatest(1, least(p_limite, 10));
$$;

revoke execute on function public.buscar_rostro(extensions.vector, integer) from public, anon, authenticated;
grant  execute on function public.buscar_rostro(extensions.vector, integer) to service_role;
