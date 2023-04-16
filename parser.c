/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   parser.c                                           :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: mazaroua <mazaroua@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2023/03/26 16:29:26 by mazaroua          #+#    #+#             */
/*   Updated: 2023/04/05 17:53:14 by mazaroua         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "minishell.h"

int	to_alloc_count(t_token_list **tokens)
{
	t_token_list	*tokens_;
	int				i;

	tokens_ = *tokens;
	i = 0;
	while (tokens_ && tokens_->type != PIPE && tokens_->type != NLINE)
	{
		if (tokens_->type == RIGHTRED || tokens_->type == LEFTRED
			|| tokens_->type == APPEND || tokens_->type == HEREDOC)
		{
			tokens_ = tokens_->next;
			if (tokens_->type == SPACE)
				tokens_ = tokens_->next;
			if (tokens_->type == WORD)
				tokens_ = tokens_->next;
				
		}
		if (tokens_ && (tokens_->type == SPACE))
			tokens_ = tokens_->next;
		if (tokens_ && (tokens_->type == WORD || tokens_->type == DOLLAR))
		{
			if (tokens_->type == DOLLAR)
				tokens_ = tokens_->next;
			while (tokens_ && (tokens_->type == WORD || tokens_->type == AFDOLLAR))
				tokens_ = tokens_->next;	
			i++;
		}
	}
	return (i);
}

void *parser(t_cmd_line **cmd_line, t_token_list *tokens)
{
    char			**str;
	t_redirections	*redirections;
	char			*tmp;
	int				i;
	if (!tokens || tokens->type == NLINE)
		return (NULL);
	while (tokens)
	{
		i = 0;
		tmp = NULL;
		str = malloc(sizeof(char *) * (to_alloc_count(&tokens) + 1));
		str[i + to_alloc_count(&tokens)] = NULL;
		redirections = NULL;
		if (tokens && tokens->type == SPACE)
		{
			tokens = tokens->next;
		}
		while (tokens && tokens->type != PIPE && tokens->type != NLINE)
		{
			if (tokens->type == WORD || tokens->type == DOLLAR)
			{
				if (tokens->type == DOLLAR && tokens->next->type == AFDOLLAR)
					tokens = tokens->next;
				if (!tmp)
					tmp = tokens->value;
				else
					tmp = ft_strjoin(tmp, tokens->value);
				str[i] = tmp;
				tokens = tokens->next;
			}	
			if (tokens && (tokens->type == RIGHTRED || tokens->type == LEFTRED
				|| tokens->type == APPEND || tokens->type == HEREDOC))
			{
				if (tokens->next->type == WORD)
				{
					fill_redirections_list(&redirections, init_redirection(tokens->type, tokens->next->value));
					tokens = tokens->next->next;
				}
				else
				{
					fill_redirections_list(&redirections, init_redirection(tokens->type, tokens->next->next->value));
					tokens = tokens->next->next->next;
				}
				if (tokens && tokens->type == SPACE)
					tokens = tokens->next;
			}
			if (tokens && tokens->type == SPACE)
			{
				if (tokens->next->type != NLINE && tokens->next->type != PIPE)
					i++;
				tokens = tokens->next;
				tmp = NULL;
			}
		}
		if (tokens && (tokens->type == NLINE || tokens->type == PIPE))
		{
			fill_cmd_line(cmd_line, init_cmdline(str, redirections, tokens));
			tokens = tokens->next;
		}
	}
	return (NULL);
}