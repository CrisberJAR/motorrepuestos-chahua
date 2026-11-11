-- =====================================================================
-- 05 · Varios administradores
--  · El administrador puede crear otros administradores o convertir a un
--    trabajador en administrador (y quitarle el rol).
--  · Protecciones: nadie puede quitarse su propio rol de administrador ni
--    desactivarse a sí mismo, y siempre debe quedar al menos un
--    administrador activo.
-- =====================================================================

create or replace function public.personal_proteger_admins()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_yo uuid := public.mi_personal_id();
begin
  if old.rol = 'admin' and old.estado = 'activo'
     and (new.rol <> 'admin' or new.estado <> 'activo') then
    if v_yo is not null and old.id = v_yo then
      raise exception 'No puedes quitarte tu propio rol de administrador ni desactivar tu cuenta. Pídeselo a otro administrador.';
    end if;
    if not exists (
      select 1 from public.personal
       where rol = 'admin' and estado = 'activo' and id <> old.id
    ) then
      raise exception 'Debe quedar al menos un administrador activo.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_personal_proteger_admins on public.personal;
create trigger trg_personal_proteger_admins
  before update of rol, estado on public.personal
  for each row execute function public.personal_proteger_admins();

-- Tampoco se puede borrar al último administrador
create or replace function public.personal_proteger_borrado_admin()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.rol = 'admin' and old.estado = 'activo' and not exists (
    select 1 from public.personal where rol = 'admin' and estado = 'activo' and id <> old.id
  ) then
    raise exception 'Debe quedar al menos un administrador activo.';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_personal_proteger_borrado_admin on public.personal;
create trigger trg_personal_proteger_borrado_admin
  before delete on public.personal
  for each row execute function public.personal_proteger_borrado_admin();
