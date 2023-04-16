/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   minishell.c                                        :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: mazaroua <mazaroua@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2023/03/06 15:26:43 by mazaroua          #+#    #+#             */
/*   Updated: 2023/04/13 16:43:14 by mazaroua         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "minishell.h"

void	free_all(t_cmd_line *cmd_line)
{
	t_cmd_line	*curr;
	t_cmd_line	*next;

	curr = cmd_line;
	while (curr)
	{
		next = curr->next;
		free(curr);
		curr = next;
	}
}

void	body(char *line, char **env,t_export **export_list,t_env_list **env_list)
{
	t_token_list	*tokens;
	t_cmd_line		*cmd_line;
	t_tools			tools;

	cmd_line = NULL;
	tokens = tokenizer(line, &tools);
	if (tokens && syntax(tokens))
	{
		// env_vars_list(&env_list, env);
		expand(&tokens, env_list);
		parser(&cmd_line, tokens);
		execution(&cmd_line, env_list,export_list);
	}
		//////////////////////////////////////////////
		// int j = 0;
		// while (cmd_line && cmd_line->str[j])
		// 	printf("|%s|\n", cmd_line->str[j++]);
		// if (cmd_line->redirections)
		// {
		// 	while (cmd_line->redirections)
		// 	{
		// 		printf("%d %s\n", cmd_line->redirections->type, cmd_line->redirections->file);
		// 		cmd_line->redirections = cmd_line->redirections->next;
		// 	}
		// }
		// puts("--------");
		// if (cmd_line)
		// 	printf("%d\n", cmd_line->separator);
		// puts("--------");
		// if (cmd_line && cmd_line->next)
		// {
		// 	int j = 0;
		// 	while (cmd_line->next->str[j])
		// 	printf("%s\n", cmd_line->next->str[j++]);
		// 	if (cmd_line->next->redirections)
		// 		printf("%d %s\n", cmd_line->next->redirections->type, cmd_line->next->redirections->file);

		// }
		///////////////////////////////////////////////

	// while (tokens)
	// {
	// 	printf("|%s| ", tokens->value);
	// 	printf("|%d|\n", tokens->type);
	// 	tokens = tokens->next;
	// }
}

char    *prompt(void)
{
    char	*line;

	line = readline("\x1B[36m""minishell$ ""\001\e[0m\002");
	if (!line)
		exit(0);
	add_history(line);
	line = remove_additional_spaces(line);
    return (line);
}

int main(int ac, char **av, char **env)
{
	(void)ac;
	(void)av;

    char	*line;
	t_export    	*export_list;
	t_env_list		*env_list;

	export_list = NULL;
	env_list = NULL;
	init_env(&export_list, &env_list, env);
    while (1)
    {
		line = prompt();
		if (!ft_strcmp(line, "exit"))
			exit(0);
		if (line)
			body(line, env,&export_list,&env_list);
    }
}