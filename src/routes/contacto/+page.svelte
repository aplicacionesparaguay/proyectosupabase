<!-- src/routes/contacto/+page.svelte -->
<script>
  let nombre = '';
  let email = '';
  let mensaje = '';

  function handleSubmit() {
    // Aquí puedes conectar con Supabase o enviar el formulario
    console.log('Formulario enviado:', { nombre, email, mensaje });
    nombre = '';
    email = '';
    mensaje = '';
  }
</script>

<main class="container">
  <h1>Contáctanos</h1>
  <form on:submit|preventDefault={handleSubmit}>
    <div class="form-group">
      <label for="nombre">Nombre</label>
      <input id="nombre" type="text" bind:value={nombre} required />
    </div>
    <div class="form-group">
      <label for="email">Email</label>
      <input id="email" type="email" bind:value={email} required />
    </div>
    <div class="form-group">
      <label for="mensaje">Mensaje</label>
      <textarea id="mensaje" bind:value={mensaje} required></textarea>
    </div>
    <button type="submit">Enviar</button>
  </form>
  <a href="/" class="back-link">Volver al inicio</a>
</main>

<style>
  .container {
    max-width: 800px;
    margin: 0 auto;
    padding: 2rem;
    font-family: Arial, sans-serif;
  }
  h1 {
    font-size: 2.5rem;
    color: #333;
    margin-bottom: 1.5rem;
  }
  .form-group {
    margin-bottom: 1.5rem;
  }
  label {
    display: block;
    font-size: 1rem;
    color: #444;
    margin-bottom: 0.5rem;
  }
  input,
  textarea {
    width: 100%;
    padding: 0.5rem;
    font-size: 1rem;
    border: 1px solid #ccc;
    border-radius: 4px;
  }
  textarea {
    min-height: 150px;
  }
  button {
    background-color: #007bff;
    color: white;
    padding: 0.75rem 1.5rem;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 1rem;
  }
  button:hover {
    background-color: #0056b3;
  }
  .back-link {
    display: inline-block;
    margin-top: 2rem;
    color: #007bff;
    text-decoration: none;
    font-weight: 500;
  }
  .back-link:hover {
    text-decoration: underline;
  }
</style>